import 'dart:js' as js;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/patient_model.dart';
import '../models/user_model.dart';
import 'audit_service.dart';

/// 保管している医療情報を書面として出力する。
///
/// 「医療情報を取り扱う情報システム・サービスの提供事業者における安全管理
/// ガイドライン第2.0版」6.2 が求める電子保存の3要件のうち**見読性**は、
///
///   > 必要に応じ電磁的記録に記録された事項を出力することにより、直ちに明瞭かつ
///   > 整然とした形式で使用に係る電子計算機その他の機器に表示し、**及び書面を
///   > 作成できるようにすること**
///
/// と定義されており、画面表示だけでは足りず紙に落とせる必要がある。
/// 本アプリが扱う薬剤服用歴相当の記録は、同ガイドライン6.4 が「取扱いに注意を
/// 要する文書等」として挙げる「診療報酬の算定上必要とされる各種文書（薬局に
/// おける薬剤服用歴の記録等）」に対応するため、この要件の対象になる。
///
/// Flutter Web は canvas 描画のためブラウザの印刷機能がそのまま使えない。
/// そこで記録内容をHTMLに組み立て、`web/index.html` の `printMedicalRecord`
/// ヘルパーで別ウィンドウに書き出して印刷ダイアログを開く。
class MedicalRecordPrintService {
  static final MedicalRecordPrintService _instance =
      MedicalRecordPrintService._internal();
  factory MedicalRecordPrintService() => _instance;
  MedicalRecordPrintService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final DateFormat _dateTime = DateFormat('yyyy/MM/dd HH:mm');

  /// 患者1名分の医療情報を書面化して印刷ダイアログを開く。
  ///
  /// 出力そのものが医療情報の持ち出しにあたるため、監査ログに記録する。
  /// 戻り値はポップアップが開けたかどうか。
  Future<bool> printPatientRecord({
    required PatientModel patient,
    required UserModel user,
  }) async {
    final medicines = await _db
        .collection('patients')
        .doc(patient.id)
        .collection('medicines')
        .orderBy('createdAt', descending: true)
        .get();

    final records = await _db
        .collection('patients')
        .doc(patient.id)
        .collection('records')
        .orderBy('takenAt', descending: true)
        .limit(200)
        .get();

    final html = _buildHtml(
      patient: patient,
      user: user,
      medicines: medicines.docs,
      records: records.docs,
    );

    final opened = js.context.callMethod('printMedicalRecord', [html]) == true;

    await AuditService().log(
      userId: user.uid,
      userName: user.name,
      action: AuditService.actionRead,
      collection: 'patients',
      documentId: patient.id,
      facilityId: patient.facilityId,
      reason: opened ? '医療情報の書面出力(印刷)' : '医療情報の書面出力(印刷)- ポップアップ拒否',
    );

    return opened;
  }

  String _buildHtml({
    required PatientModel patient,
    required UserModel user,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> medicines,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> records,
  }) {
    final now = DateTime.now();
    final b = StringBuffer();

    b.write('<!doctype html><html lang="ja"><head><meta charset="utf-8">');
    b.write('<title>${_esc(patient.name)} 様 医療情報記録</title>');
    b.write('<style>${_css()}</style></head><body>');

    // 書面のヘッダー。誰の記録を、誰が、いつ出力したかを紙面上に残す
    // (真正性の「作成に係る責任の所在を明らかにする」に対応)。
    b.write('<header class="doc-head">');
    b.write('<h1>医療情報記録</h1>');
    b.write('<table class="meta"><tbody>');
    b.write(_row('患者氏名', patient.name));
    if (patient.birthDate.isNotEmpty) {
      b.write(_row('生年月日', patient.birthDate));
    }
    if (patient.roomNumber.isNotEmpty) {
      b.write(_row('居室', patient.roomNumber));
    }
    b.write(_row('出力日時', _dateTime.format(now)));
    b.write(_row('出力者', '${user.name}（${user.role}）'));
    b.write('</tbody></table>');
    b.write('</header>');

    // 患者基本情報。腎機能・肝機能は処方判断に直結するため必ず載せる。
    b.write('<section><h2>基本情報</h2><table class="meta"><tbody>');
    b.write(_row(
      'アレルギー',
      patient.allergies.isEmpty ? '登録なし' : patient.allergies.join('、'),
    ));
    if (patient.conditions.isNotEmpty) {
      b.write(_row('既往・基礎疾患', patient.conditions.join('、')));
    }
    b.write(_row(
      '腎機能',
      [
        if (patient.egfrStatus.isNotEmpty) patient.egfrStatus,
        if (patient.egfr != null) 'eGFR ${patient.egfr}',
        if (patient.egfrNotes.isNotEmpty) patient.egfrNotes,
      ].join(' / '),
    ));
    b.write(_row(
      '肝機能',
      [
        if (patient.liverStatus.isNotEmpty) patient.liverStatus,
        if (patient.liverNotes.isNotEmpty) patient.liverNotes,
      ].join(' / '),
    ));
    if (patient.medicalNotes.isNotEmpty) {
      b.write(_row('服薬上の特記事項', patient.medicalNotes));
    }
    b.write('</tbody></table></section>');

    // 処方されている薬
    b.write('<section><h2>登録されている医薬品（${medicines.length}件）</h2>');
    if (medicines.isEmpty) {
      b.write('<p class="empty">登録なし</p>');
    } else {
      b.write('<table class="grid"><thead><tr>');
      b.write('<th>薬剤名</th><th>用法・用量</th><th>登録日</th>');
      b.write('</tr></thead><tbody>');
      for (final doc in medicines) {
        final d = doc.data();
        b.write('<tr>');
        b.write('<td>${_esc(_str(d['name']))}</td>');
        b.write('<td>${_esc(_str(d['dosage']))}</td>');
        b.write('<td>${_esc(_ts(d['createdAt']))}</td>');
        b.write('</tr>');
      }
      b.write('</tbody></table>');
    }
    b.write('</section>');

    // 服薬記録
    b.write('<section><h2>服薬記録（直近${records.length}件）</h2>');
    if (records.isEmpty) {
      b.write('<p class="empty">記録なし</p>');
    } else {
      b.write('<table class="grid"><thead><tr>');
      b.write('<th>日時</th><th>薬剤名</th><th>状態</th><th>記録者</th>');
      b.write('</tr></thead><tbody>');
      for (final doc in records) {
        final d = doc.data();
        b.write('<tr>');
        b.write('<td>${_esc(_ts(d['takenAt']))}</td>');
        b.write('<td>${_esc(_str(d['medicineName']))}</td>');
        b.write('<td>${_esc(_str(d['status']))}</td>');
        b.write('<td>${_esc(_str(d['recordedByName']))}</td>');
        b.write('</tr>');
      }
      b.write('</tbody></table>');
    }
    b.write('</section>');

    b.write('<footer class="doc-foot">');
    b.write('ファーマケア — この書面は保管中の電子記録を出力したものです。');
    b.write('出力時点の内容であり、以後の変更は反映されません。');
    b.write('</footer>');

    b.write('</body></html>');
    return b.toString();
  }

  String _row(String label, String value) =>
      '<tr><th>${_esc(label)}</th><td>${_esc(value)}</td></tr>';

  String _str(dynamic v) => v == null ? '' : v.toString();

  String _ts(dynamic v) {
    if (v is Timestamp) return _dateTime.format(v.toDate());
    if (v is DateTime) return _dateTime.format(v);
    return '';
  }

  /// HTMLとして解釈されうる文字を無害化する。
  /// 患者名や特記事項は自由入力なので、ここを通さずに埋め込んではいけない。
  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  String _css() => '''
    @page { size: A4; margin: 15mm; }
    * { box-sizing: border-box; }
    body {
      font-family: "Hiragino Sans", "Yu Gothic UI", "Noto Sans JP", sans-serif;
      color: #111; line-height: 1.7; margin: 0; font-size: 13px;
    }
    .doc-head { border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
    h1 { font-size: 20px; margin: 0 0 10px; }
    h2 { font-size: 15px; margin: 22px 0 8px; padding-left: 8px; border-left: 4px solid #1976D2; }
    section { break-inside: auto; }
    table { width: 100%; border-collapse: collapse; }
    table.meta th {
      text-align: left; width: 140px; font-weight: 600;
      padding: 4px 10px 4px 0; vertical-align: top; white-space: nowrap;
    }
    table.meta td { padding: 4px 0; }
    table.grid { border: 1px solid #999; margin-top: 6px; }
    table.grid th, table.grid td {
      border: 1px solid #999; padding: 5px 8px; text-align: left; vertical-align: top;
    }
    table.grid th { background: #f0f0f0; font-weight: 600; white-space: nowrap; }
    table.grid tr { break-inside: avoid; }
    .empty { color: #666; margin: 6px 0 0; }
    .doc-foot {
      margin-top: 26px; padding-top: 10px; border-top: 1px solid #999;
      font-size: 11px; color: #555;
    }
  ''';
}
