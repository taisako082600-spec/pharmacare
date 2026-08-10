import 'package:cloud_firestore/cloud_firestore.dart';

/// OTCトリアージ記録（患者の症状入力・AI判定結果）
class OTCTriageRecord {
  final String id;
  final String patientId;
  final String facilityId;

  // ===== OPQRST 評価フレームワーク =====
  final String symptomCategory;     // 'cold' | 'pain' | 'fever' | 'dizziness' | 'other'
  final DateTime symptomOnset;      // 症状発症時刻
  final String symptomPattern;      // 'acute' | 'chronic' | 'recurring'
  final List<String> symptomQualities; // ['咳', '鼻水', '喉痛'] など複数選択可
  final List<String> relatedFactors; // ['食後に増加', '朝に悪化'] など
  final int severityScore;          // 1-5 スケール
  final String timing;              // '朝に悪化' | '夜間に悪化' など

  // ===== レッドフラッグサイン チェック =====
  final Map<String, bool> redFlags; // key: 'highFever' | 'severeHeadache' など
                                     // value: true/false
  final Map<String, bool> consultationFlags; // redFlagsより一段弱い「受診勧奨」相当のサイン
                                              // (例: 風邪で症状が1つだけ突出、等)

  // ===== バイタルサイン(オプション、未測定ならnull) =====
  final double? spo2;
  final double? bpSystolic;
  final double? pulseRate;

  // ===== 患者コンテキスト情報 =====
  final double? egfr;               // 腎機能
  final String? liverStatus;        // 肝機能ステータス
  final List<String> allergies;     // アレルギー
  final List<String> existingConditions; // 既存疾患

  // ===== 判定結果 =====
  final String triageResult;        // 'otc_suitable' | 'consultation' | 'medical_referral'
  final String? triageExplanation;  // AI判定の詳細説明
  final List<String>? suggestedOTCs; // 推奨OTC医薬品名
  final String? pharmacistNotes;    // 薬剤師向けメモ

  // ===== 処理情報 =====
  final String conductedBy;         // スタッフ UID
  final String? conductedByName;    // スタッフ名
  final Timestamp createdAt;
  final Timestamp? updatedAt;
  final String? consultationRoomId; // 相談ルーム ID（相談接続時）

  // ===== 監査ログ =====
  final List<Map<String, dynamic>>? auditLogs;

  OTCTriageRecord({
    required this.id,
    required this.patientId,
    required this.facilityId,
    required this.symptomCategory,
    required this.symptomOnset,
    required this.symptomPattern,
    required this.symptomQualities,
    required this.relatedFactors,
    required this.severityScore,
    required this.timing,
    required this.redFlags,
    this.consultationFlags = const {},
    this.spo2,
    this.bpSystolic,
    this.pulseRate,
    this.egfr,
    this.liverStatus,
    this.allergies = const [],
    this.existingConditions = const [],
    this.triageResult = 'pending',
    this.triageExplanation,
    this.suggestedOTCs,
    this.pharmacistNotes,
    required this.conductedBy,
    this.conductedByName,
    required this.createdAt,
    this.updatedAt,
    this.consultationRoomId,
    this.auditLogs,
  });

  /// Firestore から JSON に変換
  factory OTCTriageRecord.fromJson(Map<String, dynamic> json) {
    return OTCTriageRecord(
      id: json['id'] as String,
      patientId: json['patientId'] as String,
      facilityId: json['facilityId'] as String,
      symptomCategory: json['symptomCategory'] as String,
      symptomOnset: (json['symptomOnset'] as Timestamp).toDate(),
      symptomPattern: json['symptomPattern'] as String,
      symptomQualities: List<String>.from(json['symptomQualities'] as List? ?? []),
      relatedFactors: List<String>.from(json['relatedFactors'] as List? ?? []),
      severityScore: json['severityScore'] as int? ?? 3,
      timing: json['timing'] as String? ?? '',
      redFlags: Map<String, bool>.from(json['redFlags'] as Map? ?? {}),
      consultationFlags: Map<String, bool>.from(json['consultationFlags'] as Map? ?? {}),
      spo2: (json['spo2'] as num?)?.toDouble(),
      bpSystolic: (json['bpSystolic'] as num?)?.toDouble(),
      pulseRate: (json['pulseRate'] as num?)?.toDouble(),
      egfr: (json['egfr'] as num?)?.toDouble(),
      liverStatus: json['liverStatus'] as String?,
      allergies: List<String>.from(json['allergies'] as List? ?? []),
      existingConditions: List<String>.from(json['existingConditions'] as List? ?? []),
      triageResult: json['triageResult'] as String? ?? 'pending',
      triageExplanation: json['triageExplanation'] as String?,
      suggestedOTCs: json['suggestedOTCs'] != null
          ? List<String>.from(json['suggestedOTCs'] as List)
          : null,
      pharmacistNotes: json['pharmacistNotes'] as String?,
      conductedBy: json['conductedBy'] as String,
      conductedByName: json['conductedByName'] as String?,
      createdAt: json['createdAt'] as Timestamp,
      updatedAt: json['updatedAt'] as Timestamp?,
      consultationRoomId: json['consultationRoomId'] as String?,
      auditLogs: json['auditLogs'] != null
          ? List<Map<String, dynamic>>.from(json['auditLogs'] as List)
          : null,
    );
  }

  /// JSON に変換して Firestore に保存
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'facilityId': facilityId,
      'symptomCategory': symptomCategory,
      'symptomOnset': Timestamp.fromDate(symptomOnset),
      'symptomPattern': symptomPattern,
      'symptomQualities': symptomQualities,
      'relatedFactors': relatedFactors,
      'severityScore': severityScore,
      'timing': timing,
      'redFlags': redFlags,
      'consultationFlags': consultationFlags,
      'spo2': spo2,
      'bpSystolic': bpSystolic,
      'pulseRate': pulseRate,
      'egfr': egfr,
      'liverStatus': liverStatus,
      'allergies': allergies,
      'existingConditions': existingConditions,
      'triageResult': triageResult,
      'triageExplanation': triageExplanation,
      'suggestedOTCs': suggestedOTCs,
      'pharmacistNotes': pharmacistNotes,
      'conductedBy': conductedBy,
      'conductedByName': conductedByName,
      'createdAt': createdAt,
      'updatedAt': updatedAt ?? Timestamp.now(),
      'consultationRoomId': consultationRoomId,
      'auditLogs': auditLogs,
    };
  }

  /// トリアージ結果を表示用文字列に
  String get resultLabel {
    switch (triageResult) {
      case 'otc_suitable':
        return 'OTC対応可';
      case 'consultation':
        return '薬剤師相談推奨';
      case 'medical_referral':
        return '医療機関受診推奨';
      default:
        return '判定待ち';
    }
  }

  /// トリアージ結果の背景色
  int get resultColor {
    switch (triageResult) {
      case 'otc_suitable':
        return 0xFF4CAF50; // 緑
      case 'consultation':
        return 0xFFFFC107; // 黄
      case 'medical_referral':
        return 0xFFF44336; // 赤
      default:
        return 0xFF9E9E9E; // 灰色
    }
  }

  /// 重症度スコアを表示用文字列に
  String get severityLabel {
    switch (severityScore) {
      case 1:
        return '軽度';
      case 2:
        return 'やや軽度';
      case 3:
        return '中等度';
      case 4:
        return 'やや重度';
      case 5:
        return '重度';
      default:
        return '不明';
    }
  }
}

/// トリアージフォームの入力状態管理
class OTCTriageFormState {
  String symptomCategory = 'cold'; // 初期値
  DateTime symptomOnset = DateTime.now();
  String symptomPattern = 'acute';
  List<String> symptomQualities = [];
  List<String> relatedFactors = [];
  int severityScore = 3;
  String timing = '';
  Map<String, bool> redFlags = {};
  Map<String, bool> consultationFlags = {};
  double? spo2;
  double? bpSystolic;
  double? pulseRate;

  OTCTriageFormState();
}
