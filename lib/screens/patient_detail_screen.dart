import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';
import '../models/user_model.dart';
import '../services/ai_drug_service.dart';
import '../services/audit_service.dart';
import '../services/connectivity_guard.dart';
import '../services/medical_record_print_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'qr_scanner_screen.dart';
import 'otc_triage_form_screen.dart';

/// 患者ドキュメントを更新し、変更前後の値を監査ログに残す。
///
/// 「医療情報を取り扱う情報システム・サービスの提供事業者における安全管理
/// ガイドライン第2.0版」6.2 の電子保存の要求事項のうち**真正性**が、
///
///   > 改変又は消去の事実の有無**及びその内容**を確認することができる措置を講じ、
///   > かつ、当該電磁的記録の作成に係る責任の所在を明らかにしていること
///
/// を求めているため。アレルギー・服薬上の特記事項・腎肝機能はいずれも
/// 要配慮個人情報であり、かつ処方判断に直結するので、
/// 「誰がいつ何をどう書き換えたか」を後から追えないと事故時に検証できない。
///
/// 変更前の値は [data] に含まれるキーだけに絞って記録する
/// (無関係なフィールドまで監査ログに複製すると、要配慮個人情報の保管箇所が
///  無用に増えるため)。
Future<void> _updatePatientAudited(
  PatientModel patient,
  UserModel user,
  Map<String, dynamic> data, {
  required String reason,
}) async {
  final ref = FirebaseFirestore.instance.collection('patients').doc(patient.id);

  final before = (await ref.get()).data();
  final beforeSubset = before == null
      ? null
      : {
          for (final key in data.keys)
            if (before.containsKey(key)) key: before[key],
        };

  await ref.update(data);

  await AuditService().log(
    userId: user.uid,
    userName: user.name,
    action: AuditService.actionUpdate,
    collection: 'patients',
    documentId: patient.id,
    facilityId: patient.facilityId,
    beforeData: beforeSubset,
    afterData: data,
    reason: reason,
  );
}

class PatientDetailScreen extends StatefulWidget {
  final PatientModel patient;
  final UserModel user;
  const PatientDetailScreen({super.key, required this.patient, required this.user});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // 「誰が・いつ・どの患者の医療情報を見たか」を残す。
    // ガイドライン システム運用編 17① が求める「ログイン中に操作した医療情報が
    // 特定できる」証跡のうち、参照(READ)にあたる部分。
    // 画面を開いた時点で1件記録する(タブ切替や再描画では増やさない)。
    AuditService().log(
      userId: widget.user.uid,
      userName: widget.user.name,
      action: AuditService.actionRead,
      collection: 'patients',
      documentId: widget.patient.id,
      facilityId: widget.patient.facilityId,
      reason: '患者詳細画面の表示',
    );
  }

  /// 保管している医療情報を書面として出力する（見読性の要求事項）。
  /// 出力自体が医療情報の持ち出しにあたるため、サービス側で監査ログに記録される。
  Future<void> _printRecord(PatientModel patient) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final opened = await MedicalRecordPrintService().printPatientRecord(
        patient: patient,
        user: widget.user,
      );
      if (!mounted) return;
      if (!opened) {
        msg.showSnackBar(const SnackBar(
          content: Text('ポップアップがブロックされました。ブラウザの設定で許可してください'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      msg.showSnackBar(SnackBar(
        content: Text('印刷用の書面を作成できませんでした: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isPharmacist => widget.user.isPharmacist;

  Future<void> _showFamilyShareDialog(PatientModel patient) async {
    // 既存の家族コードを確認
    final existing = await FirebaseFirestore.instance
        .collection('invite_codes')
        .where('patientId', isEqualTo: patient.id)
        .where('used', isEqualTo: false)
        .where('type', isEqualTo: 'family')
        .get();

    String code;
    if (existing.docs.isNotEmpty) {
      code = existing.docs.first.get('code') as String;
    } else {
      // 新規発行
      final rand = Random.secure();
      code = List.generate(6, (_) => rand.nextInt(10)).join();
      // ドキュメントIDはコード文字列そのもの(firestore.rules が get() で照合するため)。
      await FirebaseFirestore.instance.collection('invite_codes').doc(code).set({
        'code': code,
        'type': 'family',
        'createdBy': widget.user.uid,
        'patientId': patient.id,
        'patientName': patient.roomNumber.isNotEmpty ? patient.roomNumber : '患者',
        'facilityId': widget.user.facilityId,
        'facilityName': widget.user.facilityName,
        'used': false,
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.family_restroom, color: AppTheme.accentDeep),
            SizedBox(width: 8),
            Text('家族共有コード'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('このコードをご家族に共有してください。\nアプリの「家族」ロールで登録時に使用します。',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(color: AppTheme.canvas, borderRadius: BorderRadius.circular(12)),
              child: Text(code, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 12, color: AppTheme.accentDeep)),
            ),
            const SizedBox(height: 8),
            const Text('有効期限: 30日間', style: TextStyle(fontSize: 12, color: Colors.black38)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('コードをコピーしました'), backgroundColor: AppTheme.accentDeep),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('コピー'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentDeep, foregroundColor: Colors.white),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showAddVisitDialog() {
    DateTime visitDate = DateTime.now();
    DateTime? nextVisitDate;
    final deptCtrl = TextEditingController();
    final symptomCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final deptOptions = ['内科', '外科', '整形外科', '皮膚科', '耳鼻科', '眼科', '泌尿器科', '小児科', 'その他'];
    final timingOptions = ['朝', '昼', '夕', '就寝前', '朝・夕', '朝・昼・夕', '頓服'];

    // 複数薬剤リスト
    final medicines = <Map<String, dynamic>>[
      {'name': TextEditingController(), 'dosage': TextEditingController(), 'timing': '朝・昼・夕', 'days': TextEditingController(), 'usageNote': TextEditingController()},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('受診記録を追加',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: '処方箋のQRコードを読み取ります',
                          child: IconButton(
                            icon: const Icon(Icons.qr_code_2,
                                color: AppTheme.accentDeep),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => QRScannerScreen(
                                    patientId: widget.patient.id,
                                    patientName: _isPharmacist
                                        ? (widget.patient.roomNumber.isNotEmpty
                                            ? widget.patient.roomNumber
                                            : '患者')
                                        : widget.patient.name,
                                    user: widget.user,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppTheme.accentDeep),
                      SizedBox(width: 8),
                      Expanded(child: Text('赤い * は必須項目です', style: TextStyle(fontSize: 12, color: AppTheme.accentDeep))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 受診日
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: visitDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setModalState(() => visitDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: AppTheme.accentDeep),
                        const SizedBox(width: 8),
                        Text(
                          '受診日: ${visitDate.year}年${visitDate.month}月${visitDate.day}日',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 14, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 診療科
                const Row(
                  children: [
                    Text('診療科',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    SizedBox(width: 4),
                    Text('*', style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: deptOptions.map((d) {
                    final sel = deptCtrl.text == d;
                    return GestureDetector(
                      onTap: () =>
                          setModalState(() => deptCtrl.text = sel ? '' : d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppTheme.accentDeep
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    sel ? Colors.white : Colors.black87)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: symptomCtrl,
                  decoration: const InputDecoration(
                      labelText: '主症状（例: 発熱・咳）',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),

                const SizedBox(height: 4),
                const Divider(),
                const Row(
                  children: [
                    Text('薬剤情報',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    SizedBox(width: 4),
                    Text('*',
                        style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),

                // 薬剤リスト
                ...medicines.asMap().entries.map((e) {
                  final idx = e.key;
                  final med = e.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('第${idx + 1}薬',
                                style: const TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (medicines.length > 1)
                              GestureDetector(
                                onTap: () => setModalState(() => medicines.removeAt(idx)),
                                child: const Icon(Icons.close, size: 16, color: Colors.black38),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: med['name'] as TextEditingController,
                          decoration: InputDecoration(
                              labelText: '薬剤名',
                              suffixIcon: const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Text('*', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ),
                              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              isDense: true,
                              border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: med['dosage'] as TextEditingController,
                          decoration: const InputDecoration(
                              labelText: '1回量（例: 1錠、5mg）', isDense: true, border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4, runSpacing: 4,
                          children: timingOptions.map((t) => ChoiceChip(
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            selected: (med['timing'] as String) == t,
                            onSelected: (_) => setModalState(() => med['timing'] = t),
                            selectedColor: AppTheme.accentDeep,
                            labelStyle: TextStyle(
                                color: (med['timing'] as String) == t ? Colors.white : Colors.black87,
                                fontSize: 11),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: med['days'] as TextEditingController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: '処方日数',
                            suffixText: '日',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: med['usageNote'] as TextEditingController,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: '用法備考（例: 不均等、食前、隔日など）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // 薬剤追加ボタン
                OutlinedButton.icon(
                  onPressed: () => setModalState(() => medicines.add(
                      {'name': TextEditingController(), 'dosage': TextEditingController(), 'timing': '朝・昼・夕', 'days': TextEditingController(), 'usageNote': TextEditingController()})),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('薬を追加', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentDeep,
                    side: const BorderSide(color: AppTheme.accentDeep),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 10),

                // 次回受診日
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: nextVisitDate ??
                          DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setModalState(() => nextVisitDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 16, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(
                          nextVisitDate != null
                              ? '次回受診: ${nextVisitDate!.month}/${nextVisitDate!.day}'
                              : '次回受診日（任意）',
                          style: TextStyle(
                              fontSize: 14,
                              color: nextVisitDate != null
                                  ? Colors.black87
                                  : Colors.black38),
                        ),
                        const Spacer(),
                        if (nextVisitDate != null)
                          GestureDetector(
                            onTap: () =>
                                setModalState(() => nextVisitDate = null),
                            child: const Icon(Icons.clear,
                                size: 14, color: Colors.black38),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: '薬剤師メモ',
                      hintText: '服薬指導内容や留意事項など',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (deptCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('診療科を選択してください'), backgroundColor: Colors.orange),
                        );
                        return;
                      }

                      final validMeds = medicines.where((m) =>
                          ((m['name'] as TextEditingController).text.trim().isNotEmpty)).toList();
                      if (validMeds.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('最低1つ以上の薬剤名を入力してください'), backgroundColor: Colors.red),
                        );
                        return;
                      }

                      if (!await ConnectivityGuard.ensureOnline(context)) return;

                      final firstName = (validMeds.first['name'] as TextEditingController).text.trim();
                      final maxDays = validMeds
                          .map((m) => int.tryParse((m['days'] as TextEditingController).text.trim()) ?? 0)
                          .fold(0, (a, b) => a > b ? a : b);
                      final maxEndDate = maxDays > 0 ? visitDate.add(Duration(days: maxDays)) : null;

                      final visitRef = await FirebaseFirestore.instance
                          .collection('patients')
                          .doc(widget.patient.id)
                          .collection('visits')
                          .add({
                        'visitDate': Timestamp.fromDate(visitDate),
                        'department': deptCtrl.text.trim(),
                        'mainSymptom': symptomCtrl.text.trim(),
                        'pharmacistNote': noteCtrl.text.trim(),
                        'days': maxDays,
                        'nextVisitDate': nextVisitDate != null ? Timestamp.fromDate(nextVisitDate!) : null,
                        'addedBy': widget.user.uid,
                        'addedByName': widget.user.name,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      for (final med in validMeds) {
                        final medDays = int.tryParse((med['days'] as TextEditingController).text.trim()) ?? 0;
                        final medEndDate = medDays > 0 ? visitDate.add(Duration(days: medDays)) : null;
                        await visitRef.collection('medicines').add({
                          'name': (med['name'] as TextEditingController).text.trim(),
                          'dosage': (med['dosage'] as TextEditingController).text.trim(),
                          'frequency': med['timing'] as String,
                          'usageNote': (med['usageNote'] as TextEditingController).text.trim(),
                          'purpose': '',
                          'startDate': Timestamp.fromDate(visitDate),
                          'endDate': medEndDate != null ? Timestamp.fromDate(medEndDate) : null,
                          'days': medDays,
                          'addedBy': widget.user.uid,
                          'addedByName': widget.user.name,
                          'addedVia': 'manual',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      }

                      if (maxEndDate != null && widget.user.facilityId.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('events').add({
                          'title': '薬切れ予定',
                          'subtitle': validMeds.length > 1 ? '$firstName 他${validMeds.length - 1}種' : firstName,
                          'type': '薬切れ',
                          'date': Timestamp.fromDate(maxEndDate),
                          'facilityId': widget.user.facilityId,
                          'patientId': widget.patient.id,
                          'visitId': visitRef.id,
                          'createdBy': widget.user.uid,
                          'createdByName': widget.user.name,
                          'createdByRole': widget.user.role,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      }

                      if (nextVisitDate != null && widget.user.facilityId.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('events').add({
                          'title': '次回受診予定',
                          'subtitle': deptCtrl.text.trim().isNotEmpty ? deptCtrl.text.trim() : '受診',
                          'type': '受診',
                          'date': Timestamp.fromDate(nextVisitDate!),
                          'facilityId': widget.user.facilityId,
                          'patientId': widget.patient.id,
                          'visitId': visitRef.id,
                          'createdBy': widget.user.uid,
                          'createdByName': widget.user.name,
                          'createdByRole': widget.user.role,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      }

                      if (context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentDeep,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('記録を保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patient.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppTheme.canvas,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // 表示中に他スタッフが削除した場合、snapshotはexists:falseのまま届く
        // (hasDataはtrueのため、.data()のnon-nullキャストがそのまま例外落ちしていた)。
        if (!snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: AppTheme.canvas,
            appBar: AppBar(title: const Text('入居者情報')),
            body: const Center(child: Text('この入居者は削除されました', style: TextStyle(color: Colors.black54))),
          );
        }

        final patientData = snapshot.data!.data() as Map<String, dynamic>;
        final patient = PatientModel(
          id: widget.patient.id,
          name: patientData['name'] as String? ?? '',
          birthDate: patientData['birthDate'] as String? ?? '',
          age: patientData['age'] as int? ?? 0,
          roomNumber: patientData['roomNumber'] as String? ?? '',
          facilityId: patientData['facilityId'] as String? ?? '',
          conditions: List<String>.from(patientData['conditions'] ?? []),
          allergies: List<String>.from(patientData['allergies'] ?? []),
          egfr: (patientData['egfr'] as num?)?.toDouble(),
          egfrStatus: patientData['egfrStatus'] as String? ?? '',
          egfrNotes: patientData['egfrNotes'] as String? ?? '',
          liverStatus: patientData['liverStatus'] as String? ?? '',
          liverNotes: patientData['liverNotes'] as String? ?? '',
        );
        final isPharmacist = widget.user.isPharmacist;

        return Scaffold(
          backgroundColor: AppTheme.canvas,
          body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 190,
            pinned: true,
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            actions: [
              // 見読性(書面作成)。事業者ガイドライン第2.0版 6.2 が、保存した
              // 医療情報を「書面を作成できるようにすること」まで求めているため。
              // 家族ロールは自分の家族の記録しか開けないので、そのまま出力を許す。
              IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: '記録を印刷',
                onPressed: () => _printRecord(patient),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              // グラデーションをやめ、ホーム・一覧と同じ濃紺の面に揃える。
              background: Container(
                color: AppTheme.ink,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white,
                          child: _isPharmacist
                              ? const Icon(Icons.person_outline,
                                  size: 36, color: AppTheme.ink)
                              : Text(
                                  patient.name.isNotEmpty
                                      ? patient.name[0]
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.ink),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isPharmacist) ...[
                                Text(
                                  patient.roomNumber.isNotEmpty
                                      ? patient.roomNumber
                                      : '部屋番号未登録',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                if (patient.age > 0)
                                  Text('${patient.age}歳',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.white70)),
                              ] else ...[
                                Text(patient.name,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                                const SizedBox(height: 4),
                                if (patient.age > 0 ||
                                    patient.roomNumber.isNotEmpty)
                                  Text(
                                    '${patient.age > 0 ? "${patient.age}歳" : ""}${patient.roomNumber.isNotEmpty ? " · ${patient.roomNumber}" : ""}',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.white70),
                                  ),
                                if (patient.birthDate.isNotEmpty)
                                  Text('生年月日: ${patient.birthDate}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white60)),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  user: widget.user,
                                  roomId:
                                      '${widget.user.facilityId}_patient_${patient.id}',
                                  roomName: _isPharmacist
                                      ? (patient.roomNumber.isNotEmpty
                                          ? patient.roomNumber
                                          : '患者相談')
                                      : '${patient.name}さん',
                                ),
                              )),
                          icon: const Icon(Icons.chat_bubble_outline,
                              color: Colors.white),
                          tooltip: '相談する',
                        ),
                        if (_isPharmacist)
                          IconButton(
                            onPressed: () => _showFamilyShareDialog(patient),
                            icon: const Icon(Icons.family_restroom, color: Colors.white),
                            tooltip: '家族へ共有',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(text: 'お薬手帳'),
                Tab(text: 'バイタル'),
                Tab(text: '基本情報'),
              ],
            ),
          ),
        ],
        body: Column(
          children: [
            if (patient.allergies.isNotEmpty)
              Container(
                color: AppTheme.danger,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    const Text('アレルギー: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    Expanded(
                      child: Text(
                        patient.allergies.join(' / '),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // OTCトリアージボタン
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OTCTriageFormScreen(
                          facilityId: widget.user.facilityId,
                          patient: patient,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.health_and_safety),
                  label: const Text('症状相談'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MedicineTab(
                      patient: patient,
                      user: widget.user,
                      isPharmacist: isPharmacist),
                  _VitalsTab(patient: patient, user: widget.user),
                  _InfoTab(patient: patient, isPharmacist: isPharmacist, user: widget.user),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: isPharmacist
          ? FloatingActionButton.extended(
              onPressed: _showAddVisitDialog,
              backgroundColor: AppTheme.accentDeep,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('受診を記録',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
        );
      },
    );
  }
}

// ─── お薬手帳タブ ───────────────────────────────────────────────────

class _MedicineTab extends StatefulWidget {
  final PatientModel patient;
  final UserModel user;
  final bool isPharmacist;
  const _MedicineTab(
      {required this.patient, required this.user, required this.isPharmacist});

  @override
  State<_MedicineTab> createState() => _MedicineTabState();
}

class _MedicineTabState extends State<_MedicineTab> {
  Future<void> _logPrnIntake(
      String visitId, String medicineId, String medicineName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('頓服を記録'),
        content: Text('「$medicineName」を今服用しましたか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('記録する'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (!await ConnectivityGuard.ensureOnline(context)) return;
    await FirebaseFirestore.instance
        .collection('patients')
        .doc(widget.patient.id)
        .collection('visits')
        .doc(visitId)
        .collection('medicines')
        .doc(medicineId)
        .collection('intake_logs')
        .add({
      'takenAt': FieldValue.serverTimestamp(),
      'takenBy': widget.user.uid,
      'takenByName': widget.user.name,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('服用を記録しました'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patient.id)
          .collection('visits')
          .orderBy('visitDate', descending: true)
          .snapshots(),
      builder: (ctx, visitSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('patients')
              .doc(widget.patient.id)
              .collection('medicines')
              .orderBy('createdAt', descending: false)
              .snapshots(),
          builder: (ctx, legacySnap) {
            if (!visitSnap.hasData && !legacySnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final visitDocs = visitSnap.data?.docs ?? [];
            final legacyDocs = legacySnap.data?.docs ?? [];

            if (visitDocs.isEmpty && legacyDocs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.medical_services_outlined,
                        size: 64, color: Colors.black26),
                    const SizedBox(height: 16),
                    const Text('受診記録がありません',
                        style: TextStyle(color: Colors.black38)),
                    if (widget.isPharmacist) ...[
                      const SizedBox(height: 8),
                      const Text('右下のボタンから追加してください',
                          style:
                              TextStyle(color: Colors.black26, fontSize: 13)),
                    ],
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                ...visitDocs.map((doc) => _VisitCard(
                      visitDoc: doc,
                      patient: widget.patient,
                      isPharmacist: widget.isPharmacist,
                      user: widget.user,
                      onLogPrn: _logPrnIntake,
                    )),
                if (legacyDocs.isNotEmpty) ...[
                  if (visitDocs.isNotEmpty) const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.history,
                            size: 14, color: Colors.black38),
                        const SizedBox(width: 4),
                        const Text('以前の記録（移行前）',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.black38,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ...legacyDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _LegacyMedicineCard(data: data);
                  }),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ─── 受診カード（シール形式）──────────────────────────────────────────

class _VisitCard extends StatefulWidget {
  final QueryDocumentSnapshot visitDoc;
  final PatientModel patient;
  final bool isPharmacist;
  final UserModel user;
  final Future<void> Function(String visitId, String medicineId, String name)
      onLogPrn;

  const _VisitCard({
    required this.visitDoc,
    required this.patient,
    required this.isPharmacist,
    required this.user,
    required this.onLogPrn,
  });

  @override
  State<_VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends State<_VisitCard> {
  /// 服薬注意点を見せる相手。
  ///
  /// 以前は薬剤師だけに出していたが、それでは意味がない。
  /// 「ふらつきやすい」「低血糖に注意」といった添付文書由来の注意点は、
  /// 毎日そばにいて最初に異変に気づく介護士・看護師のための情報であり、
  /// 薬剤師は数字と薬歴から判断できる。観察する人に渡らなければ、
  /// 副作用の早期発見という目的自体が果たせない。
  ///
  /// 家族ロールは対象外にしている。閲覧専用で記録を残す手段が無いうえ、
  /// 添付文書の警告をそのまま渡すと、不安をあおったり自己判断での中止に
  /// つながりかねないため。相談導線(チャット)を経由してもらう。
  bool get _canSeeCautions =>
      widget.user.isPharmacist || widget.user.isCareWorker;

  bool _cautionLoading = false;
  List<dynamic> _cautionDrugs = [];
  String _cautionMergedSummary = '';
  String? _cautionError;
  List<String>? _cautionFetchedForNames; // 直近フェッチ済みの薬剤名リスト(重複フェッチ防止)

  Future<void> _deleteVisit(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('受診記録を削除'),
        content: const Text('この受診記録と薬剤データをすべて削除します。この操作は取り消せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    if (!await ConnectivityGuard.ensureOnline(context)) return;
    if (!context.mounted) return;

    final visitRef = widget.visitDoc.reference;
    final visitId = widget.visitDoc.id;

    // 薬剤サブコレクションを削除
    final meds = await visitRef.collection('medicines').get();
    for (final med in meds.docs) {
      final logs = await med.reference.collection('intake_logs').get();
      for (final log in logs.docs) { await log.reference.delete(); }
      await med.reference.delete();
    }
    final checks = await visitRef.collection('side_effect_checks').get();
    for (final c in checks.docs) { await c.reference.delete(); }
    await visitRef.delete();

    // 関連するカレンダーイベントも削除
    final events = await FirebaseFirestore.instance
        .collection('events')
        .where('visitId', isEqualTo: visitId)
        .get();
    for (final ev in events.docs) { await ev.reference.delete(); }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('受診記録を削除しました'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editVisit(BuildContext context, Map<String, dynamic> data, DateTime? visitDate) async {
    DateTime date = visitDate ?? DateTime.now();
    DateTime? nextVisit = (data['nextVisitDate'] as Timestamp?)?.toDate();
    final deptCtrl = TextEditingController(text: data['department'] as String? ?? '');
    final symptomCtrl = TextEditingController(text: data['mainSymptom'] as String? ?? '');
    final noteCtrl = TextEditingController(text: data['pharmacistNote'] as String? ?? '');
    final daysCtrl = TextEditingController(text: '${data['days'] ?? 0}');
    final deptOptions = ['内科', '外科', '整形外科', '皮膚科', '耳鼻科', '眼科', '泌尿器科', '小児科', 'その他'];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit, color: AppTheme.accentDeep),
                    const SizedBox(width: 8),
                    const Text('受診情報を編集', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final p = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                    if (p != null) setModal(() => date = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today, size: 16, color: AppTheme.accentDeep),
                      const SizedBox(width: 8),
                      Text('受診日: ${date.year}年${date.month}月${date.day}日'),
                      const Spacer(),
                      const Icon(Icons.edit, size: 14, color: Colors.black38),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('診療科', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: deptOptions.map((d) {
                    final sel = deptCtrl.text == d;
                    return GestureDetector(
                      onTap: () => setModal(() => deptCtrl.text = sel ? '' : d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? AppTheme.accentDeep : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(d, style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.black87)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(controller: symptomCtrl, decoration: const InputDecoration(labelText: '主症状', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: daysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '処方日数', suffixText: '日', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () async {
                    final p = await showDatePicker(context: ctx, initialDate: nextVisit ?? DateTime.now().add(const Duration(days: 14)), firstDate: DateTime.now(), lastDate: DateTime(2030));
                    if (p != null) setModal(() => nextVisit = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.event, size: 16, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(nextVisit != null ? '次回: ${nextVisit!.year}年${nextVisit!.month}月${nextVisit!.day}日' : '次回受診日（任意）',
                          style: TextStyle(color: nextVisit != null ? Colors.black87 : Colors.black38)),
                      const Spacer(),
                      if (nextVisit != null)
                        GestureDetector(onTap: () => setModal(() => nextVisit = null), child: const Icon(Icons.clear, size: 14, color: Colors.black38)),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(labelText: '薬剤師コメント', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentDeep, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('更新する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != true) return;
    if (!context.mounted || !await ConnectivityGuard.ensureOnline(context)) return;

    final days = int.tryParse(daysCtrl.text.trim()) ?? 0;
    await widget.visitDoc.reference.update({
      'visitDate': Timestamp.fromDate(date),
      'department': deptCtrl.text.trim(),
      'mainSymptom': symptomCtrl.text.trim(),
      'pharmacistNote': noteCtrl.text.trim(),
      'days': days,
      'nextVisitDate': nextVisit != null ? Timestamp.fromDate(nextVisit!) : null,
    });

    // カレンダーイベントも同期更新
    await _syncCalendarEvents(
      visitId: widget.visitDoc.id,
      visitDate: date,
      days: days,
      nextVisitDate: nextVisit,
      department: deptCtrl.text.trim(),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('受診情報を更新しました'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _syncCalendarEvents({
    required String visitId,
    required DateTime visitDate,
    required int days,
    required DateTime? nextVisitDate,
    required String department,
  }) async {
    final db = FirebaseFirestore.instance;
    final existingEvents = await db.collection('events')
        .where('visitId', isEqualTo: visitId)
        .get();

    // 既存イベントをタイプ別に取得
    DocumentSnapshot? expiryEvent;
    DocumentSnapshot? visitEvent;
    for (final doc in existingEvents.docs) {
      final type = (doc.data() as Map)['type'] as String? ?? '';
      if (type == '薬切れ') expiryEvent = doc;
      if (type == '受診') visitEvent = doc;
    }

    // 薬切れイベント：日数が設定されていれば更新、なければ削除
    if (days > 0) {
      final endDate = visitDate.add(Duration(days: days));
      if (expiryEvent != null) {
        await expiryEvent.reference.update({'date': Timestamp.fromDate(endDate)});
      }
      // 既存がなければ新規作成はしない（登録時のみ）
    } else {
      await expiryEvent?.reference.delete();
    }

    // 次回受診イベント：日付が設定されていれば更新、なければ削除
    if (nextVisitDate != null) {
      if (visitEvent != null) {
        await visitEvent.reference.update({
          'date': Timestamp.fromDate(nextVisitDate),
          'subtitle': department.isNotEmpty ? department : '受診',
        });
      }
    } else {
      await visitEvent?.reference.delete();
    }
  }

  /// 服薬注意点（添付文書ベース）を自動取得する。同じ薬剤名リストに対しては
  /// 再フェッチしない(_cautionFetchedForNamesで重複防止)。
  Future<void> _fetchCautions(List<String> medicineNames) async {
    if (_cautionLoading) return;
    setState(() => _cautionLoading = true);

    final result = await AiDrugService().fetchMedicationCautions(
      medicineNames: medicineNames,
      facilityId: widget.patient.facilityId,
      egfr: widget.patient.egfr,
      liverStatus: widget.patient.liverStatus.isNotEmpty ? widget.patient.liverStatus : null,
      age: widget.patient.age,
    );

    if (!mounted) return;
    setState(() {
      _cautionDrugs = result['drugs'] as List<dynamic>? ?? [];
      _cautionMergedSummary = result['mergedSummary'] as String? ?? '';
      _cautionError = result['error'] as String?;
      _cautionLoading = false;
      _cautionFetchedForNames = medicineNames;
    });
  }

  /// StreamBuilder内から呼ぶトリガー。薬剤名リストが直近フェッチ分と変わっていれば自動取得する。
  void _maybeAutoFetchCautions(List<String> medicineNames) {
    if (medicineNames.isEmpty) return;
    if (_cautionFetchedForNames != null &&
        _listEquals(_cautionFetchedForNames!, medicineNames)) {
      return;
    }
    if (_cautionLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchCautions(medicineNames);
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Color _timingColor(String timing) {
    if (timing.contains('朝') && timing.contains('昼') && timing.contains('夕')) {
      return Colors.blue;
    }
    if (timing.contains('朝') && timing.contains('夕')) return Colors.indigo;
    if (timing.contains('朝')) return Colors.orange;
    if (timing.contains('昼')) return Colors.green;
    if (timing.contains('夕')) return Colors.purple;
    if (timing.contains('就寝')) return Colors.teal;
    if (timing.contains('頓服')) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.visitDoc.data() as Map<String, dynamic>;
    final visitDate = (data['visitDate'] as Timestamp?)?.toDate();
    final department = data['department'] as String? ?? '';
    final mainSymptom = data['mainSymptom'] as String? ?? '';
    final pharmacistNote = data['pharmacistNote'] as String? ?? '';
    final days = data['days'] as int? ?? 0;
    final nextVisitDate = (data['nextVisitDate'] as Timestamp?)?.toDate();
    final endDate =
        days > 0 && visitDate != null ? visitDate.add(Duration(days: days)) : null;
    final daysRemaining =
        endDate?.difference(DateTime.now()).inDays;
    final patientId = widget.patient.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー（シールの上部）
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppTheme.canvas,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_hospital,
                        size: 16, color: AppTheme.accentDeep),
                    const SizedBox(width: 6),
                    Text(
                      visitDate != null
                          ? '${visitDate.year}年${visitDate.month}月${visitDate.day}日'
                          : '日付不明',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.accentDeep),
                    ),
                    if (department.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentDeep,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(department,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ),
                    ],
                    const Spacer(),
                    if (widget.isPharmacist)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: Colors.black38),
                        onSelected: (v) {
                          if (v == 'edit') _editVisit(context, data, visitDate);
                          if (v == 'delete') _deleteVisit(context);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('受診情報を編集')])),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('削除', style: TextStyle(color: Colors.red))])),
                        ],
                      ),
                  ],
                ),
                if (mainSymptom.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.sick_outlined,
                          size: 13, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text('主症状: $mainSymptom',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ],
                if (pharmacistNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.comment_outlined,
                            size: 13, color: AppTheme.accentDeep),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(pharmacistNote,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.accentDeep)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 薬剤リスト
          StreamBuilder<QuerySnapshot>(
            stream: widget.visitDoc.reference
                .collection('medicines')
                .orderBy('createdAt')
                .snapshots(),
            builder: (ctx, medSnap) {
              final medicines = medSnap.data?.docs ?? [];
              final medicineNames = medicines
                  .map((d) => (d.data() as Map<String, dynamic>)['name'] as String? ?? '')
                  .where((n) => n.isNotEmpty)
                  .toList();

              if (_canSeeCautions) _maybeAutoFetchCautions(medicineNames);

              if (!medSnap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (medicines.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('薬剤なし',
                      style: TextStyle(color: Colors.black38, fontSize: 13)),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 薬剤行
                  ...medicines.asMap().entries.map((e) {
                    final med = e.value.data() as Map<String, dynamic>;
                    final isPrn =
                        (med['frequency'] as String? ?? '').contains('頓服');
                    final color = _timingColor(med['frequency'] ?? '');
                    return Column(
                      children: [
                        if (e.key > 0)
                          Divider(height: 1, color: Colors.grey.shade100),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 4,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(med['name'] ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        if ((med['frequency'] ?? '').isNotEmpty)
                                          Text(med['frequency'],
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: color,
                                                  fontWeight: FontWeight.w500)),
                                        if ((med['dosage'] ?? '').isNotEmpty) ...[
                                          const Text(' / ',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black38)),
                                          Text(med['dosage'],
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54)),
                                        ],
                                        if ((med['days'] ?? 0) > 0) ...[
                                          const Text(' / ',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black38)),
                                          Text('${med['days']}日分',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54)),
                                        ],
                                      ],
                                    ),
                                    // 頓服 → 服用ログ
                                    if (isPrn)
                                      _PrnIntakeWidget(
                                        patientId: patientId,
                                        visitId: widget.visitDoc.id,
                                        medicineId: e.value.id,
                                        medicineName: med['name'] ?? '',
                                        onLogPrn: widget.onLogPrn,
                                      ),
                                    // 定期薬 → 本日服用チェック
                                    if (!isPrn)
                                      _DailyAdherenceButton(
                                        patientId: patientId,
                                        visitId: widget.visitDoc.id,
                                        medicineId: e.value.id,
                                        takenByName: widget.user.name,
                                        takenBy: widget.user.uid,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),

                  // 服薬注意点（添付文書ベース）― 薬剤師と介護士・看護師に自動表示
                  if (_canSeeCautions && medicineNames.isNotEmpty) ...[
                    Divider(height: 1, color: Colors.grey.shade100),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: _MedicationCautionPanel(
                        loading: _cautionLoading,
                        drugs: _cautionDrugs,
                        mergedSummary: _cautionMergedSummary,
                        error: _cautionError,
                      ),
                    ),
                  ],

                  // 副作用チェック（受診日経過後に表示）
                  //
                  // 「副作用はありましたか？」に答えられるのは、実際に様子を見ている
                  // 介護士・看護師である。薬剤師限定にしていると、記録する人と
                  // 観察する人が食い違って、結局埋まらない。記入者は checkedBy に
                  // 残るので、誰の観察かは後から辿れる。
                  if (visitDate != null &&
                      DateTime.now().isAfter(visitDate) &&
                      _canSeeCautions) ...[
                    Divider(height: 1, color: Colors.grey.shade100),
                    _SideEffectCheckWidget(
                      patientId: patientId,
                      visitId: widget.visitDoc.id,
                      checkedByName: widget.user.name,
                      checkedBy: widget.user.uid,
                    ),
                  ],
                ],
              );
            },
          ),

          // フッター（残日数・次回受診・服薬率）
          _VisitFooter(
            visitDoc: widget.visitDoc,
            patientId: patientId,
            daysRemaining: daysRemaining,
            nextVisitDate: nextVisitDate,
          ),
        ],
      ),
    );
  }
}

// ─── 受診カードフッター（残日数・服薬率）─────────────────────────────

class _VisitFooter extends StatelessWidget {
  final QueryDocumentSnapshot visitDoc;
  final String patientId;
  final int? daysRemaining;
  final DateTime? nextVisitDate;

  const _VisitFooter({
    required this.visitDoc,
    required this.patientId,
    required this.daysRemaining,
    required this.nextVisitDate,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: visitDoc.reference.collection('medicines').snapshots(),
      builder: (ctx, medSnap) {
        final medicines = medSnap.data?.docs ?? [];
        if (medicines.isEmpty && daysRemaining == null && nextVisitDate == null) {
          return const SizedBox(height: 4);
        }

        // 定期薬のみ服薬率を集計
        final regularMeds = medicines.where((m) {
          final freq = (m.data() as Map)['frequency'] as String? ?? '';
          return !freq.contains('頓服');
        }).toList();
        final totalMeds = regularMeds.length;
        final hasAdherence = totalMeds > 0;

        if (!hasAdherence && daysRemaining == null && nextVisitDate == null) {
          return const SizedBox(height: 4);
        }

        return StreamBuilder<int>(
          stream: _todayAdherenceStream(regularMeds),
          builder: (ctx2, logSnap) {
            final takenToday = logSnap.data ?? 0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppTheme.canvas,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  if (daysRemaining != null) ...[
                    Icon(Icons.timer_outlined, size: 14,
                        color: daysRemaining! <= 3 ? Colors.red : Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      daysRemaining! > 0 ? '残 ${daysRemaining!}日'
                          : daysRemaining == 0 ? '本日で終了' : '終了済',
                      style: TextStyle(
                        fontSize: 12,
                        color: daysRemaining! <= 3 ? Colors.red : Colors.black54,
                        fontWeight: daysRemaining! <= 3 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                  if (nextVisitDate != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.event, size: 14, color: Colors.teal),
                    const SizedBox(width: 4),
                    Text('次回: ${nextVisitDate!.month}/${nextVisitDate!.day}',
                        style: const TextStyle(fontSize: 12, color: Colors.teal)),
                  ],
                  const Spacer(),
                  if (hasAdherence && logSnap.hasData) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: takenToday == totalMeds
                            ? Colors.green.shade50
                            : takenToday > 0
                                ? Colors.orange.shade50
                                : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: takenToday == totalMeds
                              ? Colors.green.shade300
                              : takenToday > 0
                                  ? Colors.orange.shade300
                                  : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            takenToday == totalMeds ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 12,
                            color: takenToday == totalMeds ? Colors.green : takenToday > 0 ? Colors.orange : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '本日 $takenToday/$totalMeds',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: takenToday == totalMeds ? Colors.green.shade700 : takenToday > 0 ? Colors.orange.shade700 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 本日の服薬済み数をリアルタイムストリームで返す
  // 最初の薬のストリームを購読し、変化のたびに全薬剤の合計を再集計
  Stream<int> _todayAdherenceStream(List<QueryDocumentSnapshot> meds) {
    if (meds.isEmpty) return Stream.value(0);
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // 最初の薬の intake_logs を監視し、変化があれば全薬の合計を非同期で取得
    return meds.first.reference
        .collection('intake_logs')
        .where('takenAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('takenAt', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots()
        .asyncMap((_) => _countTodayLogs(meds));
  }

  Future<int> _countTodayLogs(List<QueryDocumentSnapshot> meds) async {
    if (meds.isEmpty) return 0;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    int count = 0;
    for (final med in meds) {
      final logs = await med.reference
          .collection('intake_logs')
          .where('takenAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('takenAt', isLessThan: Timestamp.fromDate(endOfDay))
          .limit(1)
          .get();
      if (logs.docs.isNotEmpty) count++;
    }
    return count;
  }
}

// ─── 服薬注意点パネル（②医薬品注意点表示 B案） ───────────────────────────
//
// 「服薬注意点（添付文書ベース）」。LLMの自由生成ではなく、添付文書から
// 名寄せ・抽出された注意点をそのまま表示する。統合サマリー(重複除去済み)＋
// 薬剤ごとの出典付き詳細、の二段表示。情報未整備の薬剤は隠さず明示する。

class _MedicationCautionPanel extends StatelessWidget {
  final bool loading;
  final List<dynamic> drugs;
  final String mergedSummary;
  final String? error;

  const _MedicationCautionPanel({
    required this.loading,
    required this.drugs,
    required this.mergedSummary,
    required this.error,
  });

  // pending_fetch/fetch_failed/manual_neededは内部的には別状態(自動取得中/取得失敗/手動整備待ち)
  // として区別されているため、表示文言・アイコン・色もそれぞれ分ける
  // (以前は全て同じ「添付文書 整備待ち」で見分けがつかなかった)。
  static const _statusLabels = {
    'unmatched': '情報未整備（管理者確認待ち）',
    'pending_fetch': '添付文書を自動取得中です（しばらくしてから再度ご確認ください）',
    'fetch_failed': '添付文書の自動取得に失敗しました（管理者が確認します）',
    'manual_needed': '添付文書は管理者による手動整備待ちです',
    'error': '確認中にエラーが発生しました',
  };

  static const _statusIcons = {
    'unmatched': Icons.help_outline,
    'pending_fetch': Icons.hourglass_top,
    'fetch_failed': Icons.error_outline,
    'manual_needed': Icons.edit_note,
    'error': Icons.error,
  };

  static const _statusColors = {
    'unmatched': Colors.orange,
    'pending_fetch': Colors.blueGrey,
    'fetch_failed': Colors.redAccent,
    'manual_needed': Colors.orange,
    'error': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('服薬注意点を確認中...', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('服薬注意点（添付文書ベース）: $error', style: const TextStyle(fontSize: 12, color: Colors.black38)),
      );
    }

    if (drugs.isEmpty) return const SizedBox.shrink();

    final unresolvedDrugs = drugs.where((d) {
      final status = (d as Map)['status'] as String? ?? '';
      return status != 'complete';
    }).toList();

    final hasCautions = mergedSummary.isNotEmpty ||
        drugs.any((d) => ((d as Map)['cautions'] as List?)?.isNotEmpty == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.medication_outlined, size: 15, color: AppTheme.accentDeep),
            SizedBox(width: 4),
            Text('服薬注意点（添付文書ベース）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentDeep)),
          ],
        ),
        const SizedBox(height: 6),

        if (!hasCautions && unresolvedDrugs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Text('現在服用中の薬剤に、腎機能・肝機能等に関する特記事項はありません。',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),

        // 統合サマリー
        if (mergedSummary.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.line),
            ),
            child: Text(mergedSummary, style: const TextStyle(fontSize: 12, height: 1.6)),
          ),

        // 薬剤ごとの詳細（重複統合されていない単剤ケースも含め、各薬剤の出典を明示）
        ...drugs.map((raw) {
          final d = raw as Map;
          final inputName = d['inputName'] as String? ?? '';
          final status = d['status'] as String? ?? '';
          final cautions = (d['cautions'] as List?) ?? [];

          if (status != 'complete') {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(_statusIcons[status] ?? Icons.warning_amber_rounded,
                      size: 14, color: _statusColors[status] ?? Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$inputName — ${_statusLabels[status] ?? '情報未整備'}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            );
          }

          if (cautions.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
                title: Text('▸ $inputName（${d['genericName'] ?? ''}）',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                children: cautions.map((raw) {
                  final c = raw as Map;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c['sectionNumber'] ?? ''} ${_categoryLabel(c['category'] as String? ?? '')}'.trim(),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.accentDeep),
                        ),
                        Text(c['text'] as String? ?? '', style: const TextStyle(fontSize: 12, height: 1.5)),
                        Text(
                          c['reason'] as String? ?? '',
                          style: const TextStyle(fontSize: 10.5, color: Colors.black38, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }),
      ],
    );
  }

  String _categoryLabel(String category) {
    const labels = {
      'renal_impairment': '腎機能障害患者',
      'hepatic_impairment': '肝機能障害患者',
      'elderly': '高齢者',
      'important_precautions': '重要な基本的注意',
      'major_adverse_reactions': '重大な副作用',
    };
    return labels[category] ?? category;
  }
}

// ─── 頓服服用ログウィジェット ──────────────────────────────────────────

class _PrnIntakeWidget extends StatelessWidget {
  final String patientId;
  final String visitId;
  final String medicineId;
  final String medicineName;
  final Future<void> Function(String visitId, String medicineId, String name)
      onLogPrn;

  const _PrnIntakeWidget({
    required this.patientId,
    required this.visitId,
    required this.medicineId,
    required this.medicineName,
    required this.onLogPrn,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .collection('visits')
          .doc(visitId)
          .collection('medicines')
          .doc(medicineId)
          .collection('intake_logs')
          .orderBy('takenAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (ctx, snap) {
        final logs = snap.data?.docs ?? [];
        final lastLog = logs.isNotEmpty ? logs.first : null;
        final lastTaken =
            lastLog != null ? (lastLog.data() as Map)['takenAt'] as Timestamp? : null;
        final lastTakenDate = lastTaken?.toDate();

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => onLogPrn(visitId, medicineId, medicineName),
                icon: const Icon(Icons.medication, size: 14),
                label: const Text('今飲んだ',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (lastTakenDate != null) ...[
                const SizedBox(width: 8),
                Text(
                  '最終: ${lastTakenDate.month}/${lastTakenDate.day} ${lastTakenDate.hour.toString().padLeft(2, '0')}:${lastTakenDate.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── 定期薬：本日服用チェック（観察ステータス付き）─────────────────────

class _DailyAdherenceButton extends StatelessWidget {
  final String patientId;
  final String visitId;
  final String medicineId;
  final String takenByName;
  final String takenBy;

  const _DailyAdherenceButton({
    required this.patientId,
    required this.visitId,
    required this.medicineId,
    required this.takenByName,
    required this.takenBy,
  });

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showObservationDialog(BuildContext context) async {
    String selected = '問題なし';
    final options = ['問題なし', '一部拒否', '全量拒否', '嚥下困難', '吐き出し'];
    final colors = {
      '問題なし': Colors.green,
      '一部拒否': Colors.orange,
      '全量拒否': Colors.red,
      '嚥下困難': Colors.purple,
      '吐き出し': Colors.red,
    };

    final result = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('服薬状態を記録', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final color = colors[opt] ?? Colors.grey;
              final isSelected = selected == opt;
              return GestureDetector(
                onTap: () => setState(() => selected = opt),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withValues(alpha: 0.1) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? color : Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
                          size: 16, color: isSelected ? color : Colors.grey.shade400),
                      const SizedBox(width: 10),
                      Text(opt, style: TextStyle(
                          fontSize: 13,
                          color: isSelected ? color : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                  backgroundColor: colors[selected] ?? Colors.green,
                  foregroundColor: Colors.white),
              child: const Text('記録する'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    if (!await ConnectivityGuard.ensureOnline(context)) return;
    await FirebaseFirestore.instance
        .collection('patients').doc(patientId)
        .collection('visits').doc(visitId)
        .collection('medicines').doc(medicineId)
        .collection('intake_logs')
        .add({
      'takenAt': FieldValue.serverTimestamp(),
      'takenBy': takenBy,
      'takenByName': takenByName,
      'dateKey': _todayKey(),
      'observationStatus': result,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('服薬記録: $result'),
            backgroundColor: result == '問題なし' ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayKey();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients').doc(patientId)
          .collection('visits').doc(visitId)
          .collection('medicines').doc(medicineId)
          .collection('intake_logs')
          .where('dateKey', isEqualTo: today)
          .limit(1)
          .snapshots(),
      builder: (ctx, snap) {
        final log = snap.data?.docs.isNotEmpty == true ? snap.data!.docs.first : null;
        final taken = log != null;
        final status = taken ? ((log.data() as Map)['observationStatus'] as String? ?? '済') : null;
        final isAlert = taken && status != null && status != '問題なし' && status != '済';

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GestureDetector(
            onTap: taken ? null : () => _showObservationDialog(ctx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: taken ? (isAlert ? Colors.orange.shade50 : Colors.green.shade50) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: taken ? (isAlert ? Colors.orange.shade300 : Colors.green.shade300) : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    taken ? (isAlert ? Icons.warning_amber : Icons.check_circle) : Icons.radio_button_unchecked,
                    size: 13,
                    color: taken ? (isAlert ? Colors.orange : Colors.green) : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    taken ? (status ?? '本日済') : '服薬記録',
                    style: TextStyle(
                        fontSize: 11,
                        color: taken ? (isAlert ? Colors.orange.shade700 : Colors.green) : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── 副作用チェックウィジェット ─────────────────────────────────────────

class _SideEffectCheckWidget extends StatelessWidget {
  final String patientId;
  final String visitId;
  final String checkedByName;
  final String checkedBy;

  const _SideEffectCheckWidget({
    required this.patientId,
    required this.visitId,
    required this.checkedByName,
    required this.checkedBy,
  });

  Future<void> _showCheckDialog(BuildContext context) async {
    bool hasSideEffect = false;
    String severity = '軽度';
    final descCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('副作用チェック'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('副作用はありましたか？',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => hasSideEffect = false),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !hasSideEffect
                              ? Colors.green.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: !hasSideEffect
                                  ? Colors.green
                                  : Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle,
                                color: !hasSideEffect
                                    ? Colors.green
                                    : Colors.grey),
                            const SizedBox(height: 4),
                            const Text('なし',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => hasSideEffect = true),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: hasSideEffect
                              ? Colors.red.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: hasSideEffect
                                  ? Colors.red
                                  : Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.warning_amber,
                                color: hasSideEffect
                                    ? Colors.red
                                    : Colors.grey),
                            const SizedBox(height: 4),
                            const Text('あり',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (hasSideEffect) ...[
                const SizedBox(height: 12),
                const Text('重症度',
                    style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['軽度', '中度', '重度'].map((s) => ChoiceChip(
                    label: Text(s),
                    selected: severity == s,
                    selectedColor: s == '重度'
                        ? Colors.red.shade100
                        : s == '中度'
                            ? Colors.orange.shade100
                            : Colors.yellow.shade100,
                    onSelected: (_) => setS(() => severity = s),
                  )).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '症状の詳細（任意）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentDeep,
                  foregroundColor: Colors.white),
              child: const Text('記録する'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !context.mounted) return;
    if (!await ConnectivityGuard.ensureOnline(context)) return;
    // facilityId を患者ドキュメントから取得して保存
    final patientDoc = await FirebaseFirestore.instance.collection('patients').doc(patientId).get();
    final facilityId = patientDoc.get('facilityId') as String? ?? '';
    await FirebaseFirestore.instance
        .collection('patients')
        .doc(patientId)
        .collection('visits')
        .doc(visitId)
        .collection('side_effect_checks')
        .add({
      'checkedAt': FieldValue.serverTimestamp(),
      'checkedBy': checkedBy,
      'checkedByName': checkedByName,
      'hasSideEffect': hasSideEffect,
      'severity': hasSideEffect ? severity : null,
      'description': descCtrl.text.trim(),
      'patientId': patientId,
      'facilityId': facilityId,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('副作用チェックを記録しました'),
            backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .collection('visits')
          .doc(visitId)
          .collection('side_effect_checks')
          .orderBy('checkedAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (ctx, snap) {
        final lastCheck = snap.data?.docs.isNotEmpty == true
            ? snap.data!.docs.first.data() as Map<String, dynamic>
            : null;
        final hasSideEffect = lastCheck?['hasSideEffect'] as bool?;

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              const Icon(Icons.health_and_safety_outlined,
                  size: 15, color: Colors.orange),
              const SizedBox(width: 6),
              if (lastCheck == null)
                TextButton(
                  onPressed: () => _showCheckDialog(ctx),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.orange, padding: EdgeInsets.zero),
                  child: const Text('副作用チェックを記録',
                      style: TextStyle(fontSize: 12)),
                )
              else ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasSideEffect == true
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasSideEffect == true
                        ? '副作用あり: ${lastCheck['severity'] ?? ''}'
                        : '副作用なし ✓',
                    style: TextStyle(
                        fontSize: 11,
                        color: hasSideEffect == true
                            ? Colors.red
                            : Colors.green),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _showCheckDialog(ctx),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.grey, padding: EdgeInsets.zero),
                  child: const Text('更新', style: TextStyle(fontSize: 11)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── 旧形式薬剤カード（後方互換）─────────────────────────────────────

class _LegacyMedicineCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LegacyMedicineCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data['name'] ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          if ((data['frequency'] ?? '').isNotEmpty ||
              (data['dosage'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if ((data['frequency'] ?? '').isNotEmpty) data['frequency'],
                if ((data['dosage'] ?? '').isNotEmpty) data['dosage'],
              ].join(' / '),
              style:
                  const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 基本情報タブ ─────────────────────────────────────────────────────

class _InfoTab extends StatefulWidget {
  final PatientModel patient;
  final bool isPharmacist;
  final UserModel user;
  const _InfoTab({required this.patient, required this.isPharmacist, required this.user});

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  void _showAllergyDialog() {
    final currentAllergies = List<String>.from(widget.patient.allergies);
    final ctrl = TextEditingController();
    final commonAllergens = ['ペニシリン系', 'セフェム系', 'NSAIDs', 'アスピリン', 'スルホンアミド', 'ヨード剤', '造影剤', '卵', '牛乳', '小麦'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 20),
            SizedBox(width: 8),
            Text('アレルギー情報'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 登録済み
                  if (currentAllergies.isNotEmpty) ...[
                    const Text('登録済み', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: currentAllergies.map((a) => Chip(
                        label: Text(a, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.red.shade50,
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => setDlg(() => currentAllergies.remove(a)),
                      )).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // よくあるアレルゲン
                  const Text('よく使われる', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: commonAllergens.where((a) => !currentAllergies.contains(a)).map((a) =>
                      ActionChip(
                        label: Text(a, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setDlg(() => currentAllergies.add(a)),
                        avatar: const Icon(Icons.add, size: 14),
                      )
                    ).toList(),
                  ),
                  const SizedBox(height: 12),
                  // 手動入力
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          decoration: const InputDecoration(
                            labelText: 'その他を入力',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final t = ctrl.text.trim();
                          if (t.isNotEmpty && !currentAllergies.contains(t)) {
                            setDlg(() { currentAllergies.add(t); ctrl.clear(); });
                          }
                        },
                        child: const Text('追加'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () async {
                if (!await ConnectivityGuard.ensureOnline(context)) return;
                if (!mounted || !ctx.mounted) return;
                final nav = Navigator.of(ctx);
                final msg = ScaffoldMessenger.of(context);
                try {
                  await _updatePatientAudited(
                    widget.patient,
                    widget.user,
                    {'allergies': currentAllergies},
                    reason: 'アレルギー情報の編集',
                  );
                  nav.pop();
                  msg.showSnackBar(const SnackBar(content: Text('アレルギー情報を保存しました'), backgroundColor: Colors.green));
                } catch (e) {
                  nav.pop();
                  msg.showSnackBar(SnackBar(content: Text('保存失敗: $e'), backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMedicalNotesDialog() {
    final ctrl = TextEditingController(text: widget.patient.medicalNotes);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('服薬上の特記事項'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '例: 嚥下困難のため粉砕可、一包化必要…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              if (!await ConnectivityGuard.ensureOnline(context)) return;
              if (!mounted) return;
              final nav = Navigator.of(context);
              final msg = ScaffoldMessenger.of(context);
              try {
                await _updatePatientAudited(
                  widget.patient,
                  widget.user,
                  {'medicalNotes': ctrl.text.trim()},
                  reason: '服薬上の特記事項の編集',
                );
                nav.pop();
                msg.showSnackBar(const SnackBar(content: Text('保存しました'), backgroundColor: Colors.green));
              } catch (e) {
                nav.pop();
                msg.showSnackBar(SnackBar(content: Text('保存失敗: $e'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentDeep, foregroundColor: Colors.white),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showKidneyLiverDialog() {
    final egfrCtrl = TextEditingController(
      text: widget.patient.egfr != null ? widget.patient.egfr.toString() : '',
    );
    String selectedEgfr =
        widget.patient.egfrStatus.isNotEmpty ? widget.patient.egfrStatus : '正常';
    final egfrNotesCtrl = TextEditingController(text: widget.patient.egfrNotes);
    String selectedLiver =
        widget.patient.liverStatus.isNotEmpty ? widget.patient.liverStatus : '正常';
    final liverNotesCtrl = TextEditingController(text: widget.patient.liverNotes);
    final options = ['正常', '軽度異常', '中等度', '高度'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('腎機能・肝機能を記録'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('腎機能 (eGFR)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: egfrCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'eGFR値 (mL/min/1.73m²)',
                    hintText: '例: 65.0',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('グレード',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: options.map((opt) => ChoiceChip(
                    label: Text(opt),
                    selected: selectedEgfr == opt,
                    selectedColor: opt == '正常'
                        ? Colors.green.shade100
                        : opt == '軽度異常'
                            ? Colors.yellow.shade100
                            : opt == '中等度'
                                ? Colors.orange.shade100
                                : Colors.red.shade100,
                    onSelected: (_) => setDlgState(() => selectedEgfr = opt),
                  )).toList(),
                ),
                const SizedBox(height: 10),
                const Text('詳細メモ（例：クレアチニン値など）',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 6),
                TextField(
                  controller: egfrNotesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '例：Cr 1.2, 造影剤使用時注意',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('肝機能',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: options.map((opt) => ChoiceChip(
                    label: Text(opt),
                    selected: selectedLiver == opt,
                    selectedColor: opt == '正常'
                        ? Colors.green.shade100
                        : opt == '軽度異常'
                            ? Colors.yellow.shade100
                            : opt == '中等度'
                                ? Colors.orange.shade100
                                : Colors.red.shade100,
                    onSelected: (_) => setDlgState(() => selectedLiver = opt),
                  )).toList(),
                ),
                const SizedBox(height: 10),
                const Text('詳細メモ（例：AST値、ALT値など）',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 6),
                TextField(
                  controller: liverNotesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '例：AST 45, ALT 52, 造影剤使用時注意',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () async {
                if (!await ConnectivityGuard.ensureOnline(context)) return;
                if (!mounted || !ctx.mounted) return;
                final egfrVal = double.tryParse(egfrCtrl.text.trim());
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final updateData = <String, dynamic>{
                    'egfrStatus': selectedEgfr,
                    'liverStatus': selectedLiver,
                  };
                  if (egfrVal != null) updateData['egfr'] = egfrVal;
                  if (egfrNotesCtrl.text.trim().isNotEmpty) {
                    updateData['egfrNotes'] = egfrNotesCtrl.text.trim();
                  }
                  if (liverNotesCtrl.text.trim().isNotEmpty) {
                    updateData['liverNotes'] = liverNotesCtrl.text.trim();
                  }
                  await _updatePatientAudited(
                    widget.patient,
                    widget.user,
                    updateData,
                    reason: '腎機能・肝機能の編集',
                  );
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(const SnackBar(
                      content: Text('保存しました'),
                      backgroundColor: Colors.green));
                } catch (e) {
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(SnackBar(
                      content: Text('保存失敗: $e'),
                      backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentDeep,
                  foregroundColor: Colors.white),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    final isPharmacist = widget.isPharmacist;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(title: '基本情報', items: [
          if (!isPharmacist && patient.name.isNotEmpty)
            _InfoItem(label: '氏名', value: patient.name),
          if (!isPharmacist && patient.birthDate.isNotEmpty)
            _InfoItem(label: '生年月日', value: patient.birthDate),
          if (patient.age > 0) _InfoItem(label: '年齢', value: '${patient.age}歳'),
          if (patient.roomNumber.isNotEmpty)
            _InfoItem(label: '部屋番号', value: patient.roomNumber),
        ]),

        // アレルギー情報
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: patient.allergies.isNotEmpty
                ? Border.all(color: AppTheme.danger, width: 1.5)
                : null,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18,
                      color: patient.allergies.isNotEmpty ? AppTheme.danger : Colors.grey),
                  const SizedBox(width: 8),
                  Text('アレルギー',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: patient.allergies.isNotEmpty ? AppTheme.danger : Colors.black87)),
                  const Spacer(),
                  if (isPharmacist)
                    TextButton.icon(
                      onPressed: _showAllergyDialog,
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('編集', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.danger, padding: EdgeInsets.zero),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              patient.allergies.isEmpty
                  ? const Text('アレルギーなし', style: TextStyle(color: Colors.black38, fontSize: 13))
                  : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: patient.allergies.map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(a, style: const TextStyle(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w600)),
                      )).toList(),
                    ),
            ],
          ),
        ),

        // 特記事項
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 18, color: AppTheme.textSub),
                  const SizedBox(width: 8),
                  const Text('服薬上の特記事項', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  if (isPharmacist)
                    TextButton.icon(
                      onPressed: _showMedicalNotesDialog,
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('編集', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.textSub, padding: EdgeInsets.zero),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                patient.medicalNotes.isNotEmpty ? patient.medicalNotes : '特記事項なし',
                style: TextStyle(
                    fontSize: 13,
                    color: patient.medicalNotes.isNotEmpty ? Colors.black87 : Colors.black38,
                    height: 1.6),
              ),
            ],
          ),
        ),

        if (patient.conditions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoCard(
            title: '既往歴・疾患',
            items: patient.conditions
                .map((c) => _InfoItem(label: '診断名', value: c))
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
        _KidneyLiverCard(patient: patient, onEdit: _showKidneyLiverDialog),
      ],
    );
  }
}

class _KidneyLiverCard extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback onEdit;
  const _KidneyLiverCard({required this.patient, required this.onEdit});

  Color _statusColor(String status) {
    if (status == '正常') return Colors.green;
    if (status == '軽度異常') return Colors.amber;
    if (status == '中等度') return Colors.orange;
    if (status == '高度') return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final egfr = patient.egfr;
    final egfrStatus = patient.egfrStatus;
    final liver = patient.liverStatus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart,
                  size: 18, color: AppTheme.accentDeep),
              const SizedBox(width: 8),
              const Text('腎機能・肝機能',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('記録', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentDeep,
                    padding: EdgeInsets.zero),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FunctionBadge(
                  label: '腎機能 (eGFR)',
                  value: egfr != null
                      ? '${egfr.toStringAsFixed(1)} mL/min'
                      : '未記録',
                  statusLabel: egfrStatus.isNotEmpty ? egfrStatus : '—',
                  color: egfrStatus.isNotEmpty ? _statusColor(egfrStatus) : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FunctionBadge(
                  label: '肝機能',
                  value: liver.isNotEmpty ? liver : '未記録',
                  statusLabel: liver.isNotEmpty ? liver : '—',
                  color: liver.isNotEmpty ? _statusColor(liver) : Colors.grey,
                ),
              ),
            ],
          ),
          // eGFR詳細メモ表示
          if (egfrStatus.isNotEmpty && egfrStatus != '正常') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('eGFR詳細', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentDeep)),
                  const SizedBox(height: 4),
                  Text(
                    patient.egfrNotes.isNotEmpty ? patient.egfrNotes : '詳細メモなし',
                    style: TextStyle(
                      fontSize: 12,
                      color: patient.egfrNotes.isNotEmpty ? Colors.black87 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 肝機能詳細メモ表示
          if (liver.isNotEmpty && liver != '正常') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('肝機能詳細', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 4),
                  Text(
                    patient.liverNotes.isNotEmpty ? patient.liverNotes : '詳細メモなし',
                    style: TextStyle(
                      fontSize: 12,
                      color: patient.liverNotes.isNotEmpty ? Colors.black87 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FunctionBadge extends StatelessWidget {
  final String label;
  final String value;
  final String statusLabel;
  final Color color;
  const _FunctionBadge(
      {required this.label,
      required this.value,
      required this.statusLabel,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(statusLabel,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoItem> items;
  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black54)),
          ),
          const Divider(height: 1),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                        width: 80,
                        child: Text(item.label,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black38))),
                    Expanded(
                        child: Text(item.value,
                            style: const TextStyle(fontSize: 14))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});
}

// ─── バイタル記録タブ ──────────────────────────────────────────────────

class _VitalsTab extends StatefulWidget {
  final PatientModel patient;
  final UserModel user;
  const _VitalsTab({required this.patient, required this.user});

  @override
  State<_VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends State<_VitalsTab> {
  void _showVitalOptionsMenu(BuildContext context, String vitalId, DocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('バイタル記録', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.teal),
              title: const Text('編集'),
              onTap: () {
                Navigator.pop(context);
                _showEditVitalsDialog(vitalId, doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('削除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteVitalDialog(vitalId);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.black38),
              title: const Text('キャンセル', style: TextStyle(color: Colors.black38)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditVitalsDialog(String vitalId, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final systolicCtrl = TextEditingController(text: data['systolic']?.toString() ?? '');
    final diastolicCtrl = TextEditingController(text: data['diastolic']?.toString() ?? '');
    final bloodSugarCtrl = TextEditingController(text: data['bloodSugar']?.toString() ?? '');
    final weightCtrl = TextEditingController(text: data['weight']?.toString() ?? '');
    final spO2Ctrl = TextEditingController(text: data['spO2']?.toString() ?? '');
    final tempCtrl = TextEditingController(text: data['temperature']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: data['notes']?.toString() ?? '');
    final ctx = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (builderCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(builderCtx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('バイタル記録を編集', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: systolicCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '収縮期血圧', suffixText: 'mmHg', border: OutlineInputBorder(), isDense: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: diastolicCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '拡張期血圧', suffixText: 'mmHg', border: OutlineInputBorder(), isDense: true),
                  )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: bloodSugarCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '血糖値', suffixText: 'mg/dL', border: OutlineInputBorder(), isDense: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '体重', suffixText: 'kg', border: OutlineInputBorder(), isDense: true),
                  )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: spO2Ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'SpO2', suffixText: '%', border: OutlineInputBorder(), isDense: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: tempCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '体温', suffixText: '℃', border: OutlineInputBorder(), isDense: true),
                  )),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '特記事項（任意）', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: () async {
                    final errors = <String>[];
                    final updateData = <String, dynamic>{};

                    // 血圧チェック
                    if (systolicCtrl.text.isNotEmpty) {
                      final val = int.tryParse(systolicCtrl.text);
                      if (val == null) {
                        errors.add('収縮期血圧は数値で入力してください');
                      } else if (val < 70 || val > 200) errors.add('収縮期血圧は70-200の範囲で入力してください');
                      else updateData['systolic'] = val;
                    }
                    if (diastolicCtrl.text.isNotEmpty) {
                      final val = int.tryParse(diastolicCtrl.text);
                      if (val == null) {
                        errors.add('拡張期血圧は数値で入力してください');
                      } else if (val < 40 || val > 130) errors.add('拡張期血圧は40-130の範囲で入力してください');
                      else updateData['diastolic'] = val;
                    }

                    // 血糖値チェック
                    if (bloodSugarCtrl.text.isNotEmpty) {
                      final val = int.tryParse(bloodSugarCtrl.text);
                      if (val == null) {
                        errors.add('血糖値は数値で入力してください');
                      } else if (val < 40 || val > 500) errors.add('血糖値は40-500の範囲で入力してください');
                      else updateData['bloodSugar'] = val;
                    }

                    // 体重チェック
                    if (weightCtrl.text.isNotEmpty) {
                      final val = double.tryParse(weightCtrl.text);
                      if (val == null) {
                        errors.add('体重は数値で入力してください');
                      } else if (val < 20 || val > 200) errors.add('体重は20-200kgの範囲で入力してください');
                      else updateData['weight'] = val;
                    }

                    // SpO2チェック
                    if (spO2Ctrl.text.isNotEmpty) {
                      final val = int.tryParse(spO2Ctrl.text);
                      if (val == null) {
                        errors.add('SpO2は数値で入力してください');
                      } else if (val < 70 || val > 100) errors.add('SpO2は70-100の範囲で入力してください');
                      else updateData['spO2'] = val;
                    }

                    // 体温チェック
                    if (tempCtrl.text.isNotEmpty) {
                      final val = double.tryParse(tempCtrl.text);
                      if (val == null) {
                        errors.add('体温は数値で入力してください');
                      } else if (val < 34 || val > 43) errors.add('体温は34-43℃の範囲で入力してください');
                      else updateData['temperature'] = val;
                    }

                    if (notesCtrl.text.isNotEmpty) updateData['notes'] = notesCtrl.text.trim();

                    // エラーがあれば表示
                    if (errors.isNotEmpty) {
                      if (builderCtx.mounted) {
                        ScaffoldMessenger.of(builderCtx).showSnackBar(
                          SnackBar(
                            content: Text(errors.join('\n')),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                      return;
                    }

                    // 最低1つはデータが入力されているか確認
                    if (updateData.isEmpty) {
                      if (builderCtx.mounted) {
                        ScaffoldMessenger.of(builderCtx).showSnackBar(
                          const SnackBar(
                            content: Text('最低1つ以上のデータを入力してください'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }

                    // 更新実行
                    if (!await ConnectivityGuard.ensureOnline(builderCtx)) return;
                    try {
                      await FirebaseFirestore.instance
                          .collection('patients').doc(widget.patient.id)
                          .collection('vitals').doc(vitalId)
                          .update(updateData);

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('バイタルを更新しました'), backgroundColor: Colors.teal),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('更新に失敗しました: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('更新する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteVitalDialog(String vitalId) {
    final ctx = context;
    showDialog(
      context: context,
      builder: (builderCtx) => AlertDialog(
        title: const Text('バイタル記録を削除しますか？'),
        content: const Text('この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(builderCtx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              if (!await ConnectivityGuard.ensureOnline(builderCtx)) return;
              await FirebaseFirestore.instance
                  .collection('patients').doc(widget.patient.id)
                  .collection('vitals').doc(vitalId)
                  .delete();
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('バイタルを削除しました'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddVitalsDialog() {
    final systolicCtrl = TextEditingController();
    final diastolicCtrl = TextEditingController();
    final bloodSugarCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final spO2Ctrl = TextEditingController();
    final tempCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('バイタルを記録', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: systolicCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '収縮期血圧', suffixText: 'mmHg', border: OutlineInputBorder(), isDense: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: diastolicCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '拡張期血圧', suffixText: 'mmHg', border: OutlineInputBorder(), isDense: true),
                  )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: bloodSugarCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '血糖値', suffixText: 'mg/dL', border: OutlineInputBorder(), isDense: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '体重', suffixText: 'kg', border: OutlineInputBorder(), isDense: true),
                  )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: spO2Ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'SpO2', suffixText: '%', border: OutlineInputBorder(), isDense: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: tempCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '体温', suffixText: '℃', border: OutlineInputBorder(), isDense: true),
                  )),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '特記事項（任意）', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: () async {
                    final errors = <String>[];
                    final data = <String, dynamic>{
                      'recordedAt': FieldValue.serverTimestamp(),
                      'recordedBy': widget.user.uid,
                      'recordedByName': widget.user.name,
                    };

                    // 血圧チェック
                    if (systolicCtrl.text.isNotEmpty) {
                      final val = int.tryParse(systolicCtrl.text);
                      if (val == null) {
                        errors.add('収縮期血圧は数値で入力してください');
                      } else if (val < 70 || val > 200) errors.add('収縮期血圧は70-200の範囲で入力してください');
                      else data['systolic'] = val;
                    }
                    if (diastolicCtrl.text.isNotEmpty) {
                      final val = int.tryParse(diastolicCtrl.text);
                      if (val == null) {
                        errors.add('拡張期血圧は数値で入力してください');
                      } else if (val < 40 || val > 130) errors.add('拡張期血圧は40-130の範囲で入力してください');
                      else data['diastolic'] = val;
                    }

                    // 血糖値チェック
                    if (bloodSugarCtrl.text.isNotEmpty) {
                      final val = int.tryParse(bloodSugarCtrl.text);
                      if (val == null) {
                        errors.add('血糖値は数値で入力してください');
                      } else if (val < 40 || val > 500) errors.add('血糖値は40-500の範囲で入力してください');
                      else data['bloodSugar'] = val;
                    }

                    // 体重チェック
                    if (weightCtrl.text.isNotEmpty) {
                      final val = double.tryParse(weightCtrl.text);
                      if (val == null) {
                        errors.add('体重は数値で入力してください');
                      } else if (val < 20 || val > 200) errors.add('体重は20-200kgの範囲で入力してください');
                      else data['weight'] = val;
                    }

                    // SpO2チェック
                    if (spO2Ctrl.text.isNotEmpty) {
                      final val = int.tryParse(spO2Ctrl.text);
                      if (val == null) {
                        errors.add('SpO2は数値で入力してください');
                      } else if (val < 70 || val > 100) errors.add('SpO2は70-100の範囲で入力してください');
                      else data['spO2'] = val;
                    }

                    // 体温チェック
                    if (tempCtrl.text.isNotEmpty) {
                      final val = double.tryParse(tempCtrl.text);
                      if (val == null) {
                        errors.add('体温は数値で入力してください');
                      } else if (val < 34 || val > 43) errors.add('体温は34-43℃の範囲で入力してください');
                      else data['temperature'] = val;
                    }

                    if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text.trim();

                    // エラーがあれば表示
                    if (errors.isNotEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errors.join('\n')),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                      return;
                    }

                    // 最低1つはデータが入力されているか確認（timestampなどを除く）
                    if (data.entries.where((e) => e.key != 'recordedAt' && e.key != 'recordedBy' && e.key != 'recordedByName').isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('最低1つ以上のバイタルデータを入力してください'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }

                    // 保存実行
                    if (!await ConnectivityGuard.ensureOnline(context)) return;
                    try {
                      await FirebaseFirestore.instance
                          .collection('patients').doc(widget.patient.id)
                          .collection('vitals').add(data);

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('バイタルを記録しました'), backgroundColor: Colors.teal),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('記録に失敗しました: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('保存する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddVitalsDialog,
        backgroundColor: Colors.teal,
        mini: true,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('patients').doc(widget.patient.id)
            .collection('vitals')
            .orderBy('recordedAt', descending: true)
            .limit(30)
            .snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.monitor_heart_outlined, size: 64, color: Colors.black26),
                  const SizedBox(height: 16),
                  const Text('バイタル記録がありません', style: TextStyle(color: Colors.black38)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _showAddVitalsDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('記録する'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  ),
                ],
              ),
            );
          }
          // 時系列順（古い順）に並べてグラフ用データを作成
          final chronoDocs = docs.reversed.toList();
          final bpPoints = chronoDocs
              .where((d) => (d.data() as Map)['systolic'] != null)
              .map((d) => (d.data() as Map)['systolic'] as int)
              .toList();
          final bpLabels = chronoDocs
              .where((d) => (d.data() as Map)['systolic'] != null)
              .map((d) {
                final dt = ((d.data() as Map)['recordedAt'] as Timestamp?)?.toDate();
                return dt != null ? '${dt.month}/${dt.day}' : '';
              }).toList();
          final weightPoints = chronoDocs
              .where((d) => (d.data() as Map)['weight'] != null)
              .map((d) => ((d.data() as Map)['weight'] as num).toDouble())
              .toList();
          final spO2Points = chronoDocs
              .where((d) => (d.data() as Map)['spO2'] != null)
              .map((d) => ((d.data() as Map)['spO2'] as int).toDouble())
              .toList();
          final spO2Labels = chronoDocs
              .where((d) => (d.data() as Map)['spO2'] != null)
              .map((d) {
                final dt = ((d.data() as Map)['recordedAt'] as Timestamp?)?.toDate();
                return dt != null ? '${dt.month}/${dt.day}' : '';
              }).toList();
          final bsPoints = chronoDocs
              .where((d) => (d.data() as Map)['bloodSugar'] != null)
              .map((d) => ((d.data() as Map)['bloodSugar'] as int).toDouble())
              .toList();
          final bsLabels = chronoDocs
              .where((d) => (d.data() as Map)['bloodSugar'] != null)
              .map((d) {
                final dt = ((d.data() as Map)['recordedAt'] as Timestamp?)?.toDate();
                return dt != null ? '${dt.month}/${dt.day}' : '';
              }).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      if (bpPoints.length >= 2)
                        _VitalLineChart(
                          title: '血圧推移（収縮期）',
                          values: bpPoints.map((v) => v.toDouble()).toList(),
                          labels: bpLabels,
                          color: Colors.pink,
                          unit: 'mmHg',
                          dangerHigh: 140,
                          dangerLow: 90,
                        ),
                      if (weightPoints.length >= 2) ...[
                        const SizedBox(height: 12),
                        _VitalLineChart(
                          title: '体重推移',
                          values: weightPoints,
                          labels: chronoDocs
                              .where((d) => (d.data() as Map)['weight'] != null)
                              .map((d) {
                                final dt = ((d.data() as Map)['recordedAt'] as Timestamp?)?.toDate();
                                return dt != null ? '${dt.month}/${dt.day}' : '';
                              }).toList(),
                          color: Colors.brown,
                          unit: 'kg',
                        ),
                      ],
                      if (spO2Points.length >= 2) ...[
                        const SizedBox(height: 12),
                        _VitalLineChart(
                          title: 'SpO2推移',
                          values: spO2Points,
                          labels: spO2Labels,
                          color: Colors.cyan.shade700,
                          unit: '%',
                          dangerLow: 95,
                        ),
                      ],
                      if (bsPoints.length >= 2) ...[
                        const SizedBox(height: 12),
                        _VitalLineChart(
                          title: '血糖値推移',
                          values: bsPoints,
                          labels: bsLabels,
                          color: Colors.orange.shade700,
                          unit: 'mg/dL',
                          dangerHigh: 180,
                          dangerLow: 70,
                        ),
                      ],
                      if (bpPoints.length >= 2 || weightPoints.length >= 2 || spO2Points.length >= 2 || bsPoints.length >= 2)
                        const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              // docs は descending なので最新が先頭
              final recordedAt = (data['recordedAt'] as Timestamp?)?.toDate();
              final systolic = data['systolic'] as int?;
              final diastolic = data['diastolic'] as int?;
              final bloodSugar = data['bloodSugar'] as int?;
              final weight = data['weight'] as double?;
              final spO2 = data['spO2'] as int?;
              final temperature = data['temperature'] as double?;
              final notes = data['notes'] as String?;
              final recordedByName = data['recordedByName'] as String? ?? '';

              // 血圧アラート判定
              final bpHigh = systolic != null && systolic >= 140;
              final bpLow = systolic != null && systolic < 90;
              final spO2Low = spO2 != null && spO2 < 95;
              final isAlert = bpHigh || bpLow || spO2Low;

              return GestureDetector(
                onLongPress: () => _showVitalOptionsMenu(context, docs[i].id, docs[i]),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: isAlert ? Border.all(color: Colors.red.shade200) : null,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Row(
                      children: [
                        Icon(Icons.monitor_heart, size: 16, color: isAlert ? Colors.red : Colors.teal),
                        const SizedBox(width: 6),
                        Text(
                          recordedAt != null
                              ? '${recordedAt.month}/${recordedAt.day} ${recordedAt.hour.toString().padLeft(2, '0')}:${recordedAt.minute.toString().padLeft(2, '0')}'
                              : '日時不明',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        if (isAlert)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                            child: const Text('要確認', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                          ),
                        const Spacer(),
                        if (recordedByName.isNotEmpty)
                          Text(recordedByName, style: const TextStyle(fontSize: 11, color: Colors.black38)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (systolic != null && diastolic != null)
                          _VitalChip(
                            label: '血圧',
                            value: '$systolic/$diastolic mmHg',
                            icon: Icons.favorite_outline,
                            color: bpHigh ? Colors.red : bpLow ? Colors.orange : Colors.pink,
                          ),
                        if (bloodSugar != null)
                          _VitalChip(
                            label: '血糖',
                            value: '$bloodSugar mg/dL',
                            icon: Icons.water_drop_outlined,
                            color: bloodSugar > 200 ? Colors.orange : Colors.blue,
                          ),
                        if (weight != null)
                          _VitalChip(
                            label: '体重',
                            value: '${weight.toStringAsFixed(1)} kg',
                            icon: Icons.scale_outlined,
                            color: Colors.brown,
                          ),
                        if (spO2 != null)
                          _VitalChip(
                            label: 'SpO2',
                            value: '$spO2%',
                            icon: Icons.air_outlined,
                            color: spO2Low ? Colors.red : Colors.teal,
                          ),
                        if (temperature != null)
                          _VitalChip(
                            label: '体温',
                            value: '${temperature.toStringAsFixed(1)}℃',
                            icon: Icons.thermostat_outlined,
                            color: temperature >= 37.5 ? Colors.orange : Colors.green,
                          ),
                      ],
                    ),
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(notes, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                    ],
                  ),
                ),
              );
                    },
                    childCount: docs.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── バイタル折れ線グラフ ─────────────────────────────────────────────

class _VitalLineChart extends StatelessWidget {
  final String title;
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String unit;
  final double? dangerHigh;
  final double? dangerLow;

  const _VitalLineChart({
    required this.title,
    required this.values,
    required this.labels,
    required this.color,
    required this.unit,
    this.dangerHigh,
    this.dangerLow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('${values.last.toStringAsFixed(values.last == values.last.roundToDouble() ? 0 : 1)} $unit',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: CustomPaint(
              painter: _LineChartPainter(
                values: values,
                color: color,
                dangerHigh: dangerHigh,
                dangerLow: dangerLow,
              ),
              size: const Size(double.infinity, 80),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(labels.first, style: const TextStyle(fontSize: 9, color: Colors.black38)),
              if (labels.length > 2) Text(labels[labels.length ~/ 2], style: const TextStyle(fontSize: 9, color: Colors.black38)),
              Text(labels.last, style: const TextStyle(fontSize: 9, color: Colors.black38)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? dangerHigh;
  final double? dangerLow;

  const _LineChartPainter({required this.values, required this.color, this.dangerHigh, this.dangerLow});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).clamp(1.0, double.infinity);
    final padding = range * 0.2;
    final low = minV - padding;
    final high = maxV + padding;

    double toY(double v) => size.height - (v - low) / (high - low) * size.height;
    double toX(int i) => i / (values.length - 1) * size.width;

    // 危険ライン
    if (dangerHigh != null && dangerHigh! >= low && dangerHigh! <= high) {
      final dangerPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final y = toY(dangerHigh!);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), dangerPaint);
    }

    // グラデーション塗りつぶし
    final fillPath = Path();
    fillPath.moveTo(toX(0), toY(values[0]));
    for (int i = 1; i < values.length; i++) {
      final x0 = toX(i - 1); final y0 = toY(values[i - 1]);
      final x1 = toX(i); final y1 = toY(values[i]);
      final cx = (x0 + x1) / 2;
      fillPath.cubicTo(cx, y0, cx, y1, x1, y1);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // 折れ線
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final linePath = Path();
    linePath.moveTo(toX(0), toY(values[0]));
    for (int i = 1; i < values.length; i++) {
      final x0 = toX(i - 1); final y0 = toY(values[i - 1]);
      final x1 = toX(i); final y1 = toY(values[i]);
      final cx = (x0 + x1) / 2;
      linePath.cubicTo(cx, y0, cx, y1, x1, y1);
    }
    canvas.drawPath(linePath, linePaint);

    // データ点
    final dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final dotBorder = Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke;
    for (int i = 0; i < values.length; i++) {
      final p = Offset(toX(i), toY(values[i]));
      canvas.drawCircle(p, 3, dotPaint);
      canvas.drawCircle(p, 3, dotBorder);
    }

    // 最新値ラベル
    final lastX = toX(values.length - 1);
    final lastY = toY(values.last);
    final textPainter = TextPainter(
      text: TextSpan(
        text: values.last.toStringAsFixed(values.last == values.last.roundToDouble() ? 0 : 1),
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(lastX - textPainter.width - 4, lastY - textPainter.height - 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _VitalChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _VitalChip({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9, color: color)),
              Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}
