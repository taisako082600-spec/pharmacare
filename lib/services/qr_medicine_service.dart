import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class QRMedicineService {
  static final QRMedicineService _instance = QRMedicineService._internal();
  factory QRMedicineService() => _instance;
  QRMedicineService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 複数QRコード（リスト）からパース
  List<Map<String, dynamic>>? parseMultipleQRCodes(List<String> codes) {
    if (codes.isEmpty) return null;

    final first = codes.first.trim();

    // JAHISTC01: 標準お薬手帳QR
    if (first.startsWith('JAHISTC01') || first.contains('JAHISTC01')) {
      return _parseJahisMultiple(codes);
    }

    // 処方箋QR混在形式（JAHISTC07ヘッダー + 薬品QR群）
    if (codes.any((c) => c.trim().startsWith('JAHISTC'))) {
      final medicines = <Map<String, dynamic>>[];
      for (final code in codes) {
        if (code.trim().startsWith('JAHISTC')) continue; // ヘッダーQRはスキップ
        final m = _parsePrescriptionQR(code.trim());
        if (m != null) medicines.add(m);
      }
      if (medicines.isNotEmpty) return medicines;
    }

    // JAHIS（JAHISTC01以外）
    if (_isJahis(first)) return _parseJahisMultiple(codes);

    // 非JAHIS: 全コードを結合して従来パーサへ
    return parseQRCode(codes.join('\n'));
  }

  /// 処方箋QR（非JAHIS形式）パーサ
  /// QR2例: `みみ・はな・のど岡医院,40,1,0214619クラリスロマイシン錠２００mg「大正」`
  /// QR3例: `49003F2283カルボシステイン錠５００mg「トーワ」2233002F2111`
  Map<String, dynamic>? _parsePrescriptionQR(String data) {
    if (data.isEmpty) return null;

    if (data.contains(',')) {
      // カンマ区切り形式: 最後のフィールド（または日本語を含むフィールド）を使用
      final fields = _csvSplit(data);
      for (int i = fields.length - 1; i >= 0; i--) {
        final name = _extractDrugName(fields[i]);
        if (name != null && name.length > 2) {
          return {'name': name, 'dosage': '', 'frequency': '', 'purpose': ''};
        }
      }
    } else {
      // カンマなし形式: コード+薬品名+コード
      final name = _extractDrugName(data);
      if (name != null && name.isNotEmpty) {
        return {'name': name, 'dosage': '', 'frequency': '', 'purpose': ''};
      }
    }
    return null;
  }

  /// テキストから薬品名部分を抽出（先頭・末尾の英数字コードを除去）
  String? _extractDrugName(String text) {
    // 最初の日本語文字（ひらがな・カタカナ・漢字）の位置を探す
    int start = -1;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if ((code >= 0x3040 && code <= 0x30FF) || // ひらがな・カタカナ
          (code >= 0x4E00 && code <= 0x9FFF) || // CJK統合漢字
          (code >= 0xFF00 && code <= 0xFFEF)) {  // 全角文字
        start = i;
        break;
      }
    }
    if (start < 0) return null;

    // 末尾の英数字コードを除去（例: 2233002F2111）
    var end = text.length;
    final trailingCode = RegExp(r'[A-Za-z0-9]{6,}$');
    final m = trailingCode.firstMatch(text);
    if (m != null && m.start > start) end = m.start;

    return text.substring(start, end).trim();
  }

  /// 単一QR文字列からパース（後方互換）
  List<Map<String, dynamic>>? parseQRCode(String qrData) {
    try {
      final trimmed = qrData.trim();

      if (_isJahis(trimmed)) return _parseJahisMultiple([trimmed]);
      if (trimmed.startsWith('[')) return _parseJsonArray(trimmed);
      if (trimmed.startsWith('{')) {
        final s = _parseJsonObject(trimmed);
        return s != null ? [s] : null;
      }
      if (trimmed.contains('\n\n')) return _parseMultiBlockFormat(trimmed);
      if (trimmed.contains('\n') && trimmed.contains(',')) return _parseCsvMultiLine(trimmed);
      if (trimmed.contains(',')) {
        final s = _parseCsvSingleLine(trimmed);
        return s != null ? [s] : null;
      }
      if (trimmed.isNotEmpty) {
        final s = _parseTextLine(trimmed);
        return s != null ? [s] : null;
      }
      return null;
    } catch (e) {
      debugPrint('QR parse error: $e');
      return null;
    }
  }

  // ─── JAHIS電子版お薬手帳 (Ver1.0〜2.5) ───────────────────────────

  bool _isJahis(String data) =>
      data.contains('JAHISTC') || data.contains('JAHIS');

  /// 複数QRを順番に結合してパース
  List<Map<String, dynamic>>? _parseJahisMultiple(List<String> codes) {
    // シーケンス番号でソート（JAHISTC01,Ver2,1,3 の3番目の数字）
    final sorted = List<String>.from(codes)
      ..sort((a, b) => _jahisSeq(a).compareTo(_jahisSeq(b)));

    // 全行を結合（2枚目以降のJAHISヘッダ行は除外）
    final allLines = <String>[];
    for (int i = 0; i < sorted.length; i++) {
      final lines = sorted[i].split(RegExp(r'\r?\n'));
      for (final line in lines) {
        if (line.isEmpty) continue;
        // JAHIS先頭行はシーケンス情報なのでスキップ（2枚目以降）
        if (i > 0 && line.toUpperCase().contains('JAHIS')) continue;
        allLines.add(line);
      }
    }

    return _parseJahisLines(allLines);
  }

  int _jahisSeq(String qr) {
    final first = qr.split(RegExp(r'\r?\n')).first;
    final parts = _csvSplit(first);
    // JAHISTC01,Ver2,1,3 → インデックス2がシーケンス番号
    if (parts.length >= 3) return int.tryParse(parts[2].trim()) ?? 1;
    return 1;
  }

  List<Map<String, dynamic>>? _parseJahisLines(List<String> lines) {
    final medicines = <Map<String, dynamic>>[];
    Map<String, dynamic>? cur;

    for (final line in lines) {
      final parts = _csvSplit(line);
      if (parts.isEmpty) continue;

      final recNo = int.tryParse(parts[0].trim());
      if (recNo == null) continue; // ヘッダ行等はスキップ

      // レコード51: 薬品情報（新しい薬剤の始まり）
      if (recNo == 51) {
        if (cur != null) medicines.add(cur);
        // 51,YJコード,薬品名,規格,用量,用量単位,...
        final name    = _field(parts, 2);
        final spec    = _field(parts, 3); // 規格
        final dose    = _field(parts, 4);
        final unit    = _field(parts, 5);
        cur = {
          'name': name,
          'dosage': [spec, dose, unit].where((s) => s.isNotEmpty).join(' '),
          'frequency': '',
          'purpose': '',
        };
      }
      // レコード101: 薬品名カナ（無視）
      // レコード201: 用法
      else if (recNo == 201 && cur != null) {
        // 201,用法コード,用法名称
        final usage = _field(parts, 2).isNotEmpty ? _field(parts, 2) : _field(parts, 1);
        if (usage.isNotEmpty) cur['frequency'] = usage;
      }
      // レコード211: 1日回数補足
      else if (recNo == 211 && cur != null) {
        final times = _field(parts, 1);
        if (times.isNotEmpty && (cur['frequency'] as String).isEmpty) {
          cur['frequency'] = '1日$times回';
        }
      }
      // レコード221: 調剤数量
      else if (recNo == 221 && cur != null) {
        // 221,調剤数量,調剤単位
        final qty  = _field(parts, 1);
        final unit = _field(parts, 2);
        if (qty.isNotEmpty) {
          cur['purpose'] = '$qty$unit';
        }
      }
      // レコード281: 連絡・注意事項（purposeに追記）
      else if (recNo == 281 && cur != null) {
        final note = _field(parts, 1);
        if (note.isNotEmpty) {
          final prev = cur['purpose'] as String;
          cur['purpose'] = prev.isNotEmpty ? '$prev / $note' : note;
        }
      }
    }

    if (cur != null) medicines.add(cur);
    return medicines.isNotEmpty ? medicines : null;
  }

  String _field(List<String> parts, int i) =>
      i < parts.length ? parts[i].trim() : '';

  /// RFC4180準拠のCSVパーサ（ダブルクォート・フィールド内改行対応）
  List<String> _csvSplit(String line) {
    final result = <String>[];
    var inQ = false;
    final buf = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQ && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"'); i++;
        } else {
          inQ = !inQ;
        }
      } else if (c == ',' && !inQ) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    result.add(buf.toString());
    return result;
  }

  // ─── 非JAHIS パーサ群（後方互換） ─────────────────────────────────

  List<Map<String, dynamic>>? _parseJsonArray(String json) {
    try {
      final list = jsonDecode(json) as List;
      final result = list.map((item) {
        final m = item as Map<String, dynamic>;
        return {
          'name': m['name'] ?? m['薬剤名'] ?? '',
          'dosage': m['dose'] ?? m['dosage'] ?? m['用量'] ?? '',
          'frequency': m['frequency'] ?? m['timing'] ?? m['用法'] ?? '朝・昼・夕',
          'purpose': m['purpose'] ?? m['indication'] ?? m['効能'] ?? '',
        };
      }).toList();
      return result.isNotEmpty ? result : null;
    } catch (_) { return null; }
  }

  Map<String, dynamic>? _parseJsonObject(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return {
        'name': m['name'] ?? m['薬剤名'] ?? '',
        'dosage': m['dose'] ?? m['dosage'] ?? m['用量'] ?? '',
        'frequency': m['frequency'] ?? m['timing'] ?? m['用法'] ?? '朝・昼・夕',
        'purpose': m['purpose'] ?? m['indication'] ?? m['効能'] ?? '',
      };
    } catch (_) { return null; }
  }

  List<Map<String, dynamic>>? _parseMultiBlockFormat(String data) {
    final blocks = data.split('\n\n');
    final result = <Map<String, dynamic>>[];
    for (final block in blocks) {
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      result.add({
        'name': lines[0],
        'dosage': lines.length > 1 ? lines[1] : '',
        'frequency': lines.length > 2 ? lines[2] : '朝・昼・夕',
        'purpose': lines.length > 3 ? lines[3] : '',
      });
    }
    return result.isNotEmpty ? result : null;
  }

  List<Map<String, dynamic>>? _parseCsvMultiLine(String data) {
    final lines = data.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final result = <Map<String, dynamic>>[];
    for (final line in lines) {
      final m = _parseCsvSingleLine(line);
      if (m != null) result.add(m);
    }
    return result.isNotEmpty ? result : null;
  }

  Map<String, dynamic>? _parseCsvSingleLine(String csv) {
    final parts = csv.split(',').map((s) => s.trim()).toList();
    if (parts.isEmpty || parts[0].isEmpty) return null;
    return {
      'name': parts[0],
      'dosage': parts.length > 1 ? parts[1] : '',
      'frequency': parts.length > 2 ? parts[2] : '朝・昼・夕',
      'purpose': parts.length > 3 ? parts[3] : '',
    };
  }

  Map<String, dynamic>? _parseTextLine(String text) {
    final parts = text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return {
      'name': parts[0],
      'dosage': parts.length > 1 ? parts[1] : '',
      'frequency': parts.length > 2 ? parts[2] : '朝・昼・夕',
      'purpose': parts.length > 3 ? parts.sublist(3).join(' ') : '',
    };
  }

  // ─── 登録 ──────────────────────────────────────────────────────────

  /// 受診記録 + 薬剤を visits サブコレクションへ登録し、カレンダーイベントも作成
  Future<({String? visitId, int success, int failed})> registerVisitWithMedicines({
    required String patientId,
    required DateTime visitDate,
    required String department,
    required String mainSymptom,
    required String pharmacistNote,
    required List<Map<String, dynamic>> medicines,
    required String addedBy,
    required String addedByName,
    required String facilityId,
    DateTime? nextVisitDate,
  }) async {
    try {
      final maxDays = medicines
          .map((m) => (m['days'] is int ? m['days'] as int : int.tryParse(m['days']?.toString() ?? '') ?? 0))
          .fold(0, (a, b) => a > b ? a : b);

      final visitRef = await _db
          .collection('patients')
          .doc(patientId)
          .collection('visits')
          .add({
        'visitDate': Timestamp.fromDate(visitDate),
        'department': department,
        'mainSymptom': mainSymptom,
        'pharmacistNote': pharmacistNote,
        'days': maxDays,
        'nextVisitDate':
            nextVisitDate != null ? Timestamp.fromDate(nextVisitDate) : null,
        'addedBy': addedBy,
        'addedByName': addedByName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      int success = 0, failed = 0;
      final maxEndDate = maxDays > 0 ? visitDate.add(Duration(days: maxDays)) : null;

      for (final med in medicines) {
        try {
          final medDays = med['days'] is int ? med['days'] as int : int.tryParse(med['days']?.toString() ?? '') ?? 0;
          final medEndDate = medDays > 0 ? visitDate.add(Duration(days: medDays)) : null;
          await visitRef.collection('medicines').add({
            'name': (med['name'] ?? '').toString().trim(),
            'dosage': (med['dosage'] ?? '').toString().trim(),
            'frequency': (med['frequency'] ?? '').toString().trim(),
            'usageNote': (med['usageNote'] ?? '').toString().trim(),
            'purpose': (med['purpose'] ?? '').toString().trim(),
            'startDate': Timestamp.fromDate(visitDate),
            'endDate': medEndDate != null ? Timestamp.fromDate(medEndDate) : null,
            'days': medDays,
            'addedBy': addedBy,
            'addedByName': addedByName,
            'addedVia': med['addedVia']?.toString() ?? 'QR',
            'createdAt': FieldValue.serverTimestamp(),
          });
          success++;
        } catch (e) {
          debugPrint('Medicine registration error: $e');
          failed++;
        }
      }

      if (maxEndDate != null && facilityId.isNotEmpty) {
        try {
          await _db.collection('events').add({
            'title': '薬切れ予定',
            'subtitle': '${medicines.length}種類の薬が終了',
            'type': '薬切れ',
            'date': Timestamp.fromDate(maxEndDate),
            'facilityId': facilityId,
            'patientId': patientId,
            'visitId': visitRef.id,
            'createdBy': addedBy,
            'createdByName': addedByName,
            'createdByRole': 'pharmacist',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Calendar event creation error: $e');
        }
      }

      if (nextVisitDate != null && facilityId.isNotEmpty) {
        try {
          await _db.collection('events').add({
            'title': '次回受診予定',
            'subtitle': department.isNotEmpty ? department : '受診',
            'type': '受診',
            'date': Timestamp.fromDate(nextVisitDate),
            'facilityId': facilityId,
            'patientId': patientId,
            'visitId': visitRef.id,
            'createdBy': addedBy,
            'createdByName': addedByName,
            'createdByRole': 'pharmacist',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Calendar event creation error: $e');
        }
      }

      return (visitId: visitRef.id, success: success, failed: failed);
    } catch (e) {
      debugPrint('Visit registration error: $e');
      return (visitId: null, success: 0, failed: medicines.length);
    }
  }

  Future<({int success, int failed})> registerMedicines({
    required String patientId,
    required List<Map<String, dynamic>> medicines,
    required String addedByName,
  }) async {
    int success = 0, failed = 0;
    for (final med in medicines) {
      try {
        await _db.collection('patients').doc(patientId).collection('medicines').add({
          'name': (med['name'] ?? '').toString().trim(),
          'dosage': (med['dosage'] ?? '').toString().trim(),
          'frequency': (med['frequency'] ?? '朝・昼・夕').toString().trim(),
          'purpose': (med['purpose'] ?? '').toString().trim(),
          'addedByName': addedByName,
          'addedVia': 'QR',
          'createdAt': FieldValue.serverTimestamp(),
        });
        success++;
      } catch (e) {
        debugPrint('Medicine registration error: $e');
        failed++;
      }
    }
    return (success: success, failed: failed);
  }

  /// 後方互換：単剤登録
  Future<bool> registerMedicine({
    required String patientId,
    required String name,
    required String dosage,
    required String frequency,
    required String purpose,
    required String addedByName,
  }) async {
    final result = await registerMedicines(
      patientId: patientId,
      medicines: [{'name': name, 'dosage': dosage, 'frequency': frequency, 'purpose': purpose}],
      addedByName: addedByName,
    );
    return result.failed == 0;
  }
}
