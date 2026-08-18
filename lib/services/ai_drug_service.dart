import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';

/// Claude API への直接呼び出しは行わず、Go製LLMプロキシ(llm-proxy/)を経由する。
/// プロキシがプロンプトキャッシュ・トークン上限管理・OTCトリアージの安全弁ロジックを担う。
/// 詳細は llm-proxy/README.md および memory の go_llm_proxy_plan を参照。
class AiDrugService {
  static final AiDrugService _instance = AiDrugService._internal();
  factory AiDrugService() => _instance;
  AiDrugService._internal();

  // Goプロキシのベースエンドポイント。
  // ここに書いてあるのはローカル開発用のデフォルト値。本番ビルドは
  // `--dart-define=LLM_PROXY_URL=...` でCloud RunのURLを注入して上書きする
  // (本番URLはリポジトリに書かず、ビルド時に渡す)。
  static const String _proxyBaseUrl = String.fromEnvironment(
    'LLM_PROXY_URL',
    defaultValue: 'http://localhost:8081',
  );

  Future<String?> _authHeaderToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('Firebase ID token取得エラー: $e');
      return null;
    }
  }

  /// 服薬注意点（添付文書ベース）の取得。プロキシの POST /v1/analyze-medication に対応。
  /// ②医薬品注意点表示 B案(根拠付き個別最適化)。自由記述生成ではなく、
  /// 添付文書から名寄せ・抽出された注意点をそのまま返す(判定はサーバー側で完結)。
  /// 戻り値の 'drugs' には薬剤ごとの状態(complete/unmatched/pending_fetch等)と
  /// 出典付きの注意点(cautions)が入る。'mergedSummary' は複数薬剤の重複統合が
  /// 必要な場合のみLLMが生成する(該当なしなら空文字)。
  Future<Map<String, dynamic>> fetchMedicationCautions({
    required List<String> medicineNames,
    String? facilityId,
    double? egfr,
    String? liverStatus,
    int? age,
  }) async {
    if (medicineNames.isEmpty) {
      return {'drugs': [], 'mergedSummary': '', 'error': null};
    }

    try {
      final token = await _authHeaderToken();
      final response = await http
          .post(
            Uri.parse('$_proxyBaseUrl/v1/analyze-medication'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'medicineNames': medicineNames,
              if (facilityId != null && facilityId.isNotEmpty) 'facilityId': facilityId,
              if (egfr != null) 'egfr': egfr,
              if (liverStatus != null && liverStatus.isNotEmpty) 'liverStatus': liverStatus,
              if (age != null) 'age': age,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'drugs': data['drugs'] ?? [], 'mergedSummary': data['mergedSummary'] ?? '', 'error': null};
      }
      debugPrint('LLMプロキシ エラー: ${response.statusCode} ${response.body}');
      return {'drugs': [], 'mergedSummary': '', 'error': 'サーバーエラー（${response.statusCode}）'};
    } catch (e) {
      debugPrint('LLMプロキシ 通信エラー: $e');
      return {'drugs': [], 'mergedSummary': '', 'error': 'プロキシに接続できません'};
    }
  }

  /// OTCトリアージのAI解説文取得。プロキシの POST /v1/triage に対応。
  /// 戻り値の triageResult はサーバー側の決定論的ロジック(DetermineTriageResult)が
  /// 権威を持つ判定結果であり、Flutter側では上書きしない。
  Future<Map<String, dynamic>> analyzeTriage({
    required String symptomCategory,
    required List<String> symptomQualities,
    required int severityScore,
    required Map<String, bool> redFlags,
    Map<String, bool> consultationFlags = const {},
    double? spo2,
    double? bpSystolic,
    double? pulseRate,
    double? egfr,
    String? liverStatus,
    List<String> medicineNames = const [],
  }) async {
    try {
      final token = await _authHeaderToken();
      final response = await http
          .post(
            Uri.parse('$_proxyBaseUrl/v1/triage'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'symptomCategory': symptomCategory,
              'symptomQualities': symptomQualities,
              'severityScore': severityScore,
              'redFlags': redFlags,
              'consultationFlags': consultationFlags,
              if (spo2 != null) 'spo2': spo2,
              if (bpSystolic != null) 'bpSystolic': bpSystolic,
              if (pulseRate != null) 'pulseRate': pulseRate,
              if (egfr != null) 'egfr': egfr,
              if (liverStatus != null && liverStatus.isNotEmpty) 'liverStatus': liverStatus,
              'medicineNames': medicineNames,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('トリアージプロキシ エラー: ${response.statusCode} ${response.body}');
    } catch (e) {
      debugPrint('トリアージプロキシ 通信エラー: $e');
    }

    // プロキシに接続できない場合でも、レッドフラッグに基づく最低限の安全弁だけは
    // アプリ単体で計算して返す(Goサーバー側の DetermineTriageResult と同じロジック)。
    return _fallbackTriageResult(
      symptomCategory,
      redFlags,
      consultationFlags,
      severityScore,
      spo2: spo2,
      bpSystolic: bpSystolic,
    );
  }

  /// 管理者専用: 「取得待ちリスト」の薬剤についてPMDA添付文書の自動取得を実行する。
  /// プロキシの POST /v1/admin/fetch-drug-label に対応。管理者権限はサーバー側
  /// (isAdminUser、users/{uid}.isAdmin)で検証されるため、Flutter側では呼び出すだけでよい。
  /// searchName は省略可(省略時は genericName でPMDA検索する。実際に患者手帳へ
  /// 入力された商品名を渡す方が検索がヒットしやすい)。
  Future<Map<String, dynamic>> adminFetchDrugLabel({
    required String genericName,
    String? searchName,
  }) async {
    try {
      final token = await _authHeaderToken();
      final response = await http
          .post(
            Uri.parse('$_proxyBaseUrl/v1/admin/fetch-drug-label'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'genericName': genericName,
              if (searchName != null && searchName.isNotEmpty) 'searchName': searchName,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('管理者用取得プロキシ エラー: ${response.statusCode} ${response.body}');
      return {'success': false, 'reason': 'サーバーエラー（${response.statusCode}）'};
    } catch (e) {
      debugPrint('管理者用取得プロキシ 通信エラー: $e');
      return {'success': false, 'reason': 'プロキシに接続できません: $e'};
    }
  }

  // 'consciousness'(意識障害)カテゴリはレッドフラッグの選択状態によらず常に受診推奨とする。
  // llm-proxy/redflag.go の alwaysReferCategories と同じ特別ルール。
  static const _alwaysReferCategories = {'consciousness'};

  // バイタル実測値からの自動レッドフラッグ合成。llm-proxy/redflag.go の
  // ApplyVitalsRedFlags と同じ閾値・ロジック(必ず同期させること)。
  static const _vitalsLowSpO2Threshold = 90.0;
  static const _vitalsSevereHypertensionSystolic = 180.0;
  // ショック/qSOFAの収縮期血圧項目。カテゴリを問わない。
  static const _vitalsHypotensionSystolic = 100.0;

  Map<String, dynamic> _fallbackTriageResult(
    String symptomCategory,
    Map<String, bool> redFlags,
    Map<String, bool> consultationFlags,
    int severityScore, {
    double? spo2,
    double? bpSystolic,
  }) {
    final effectiveRedFlags = {...redFlags};
    if (spo2 != null && spo2 < _vitalsLowSpO2Threshold) {
      effectiveRedFlags['vitalsLowSpO2'] = true;
    }
    if (bpSystolic != null &&
        bpSystolic >= _vitalsSevereHypertensionSystolic &&
        symptomCategory == 'headache') {
      effectiveRedFlags['vitalsSevereHypertension'] = true;
    }
    if (bpSystolic != null && bpSystolic <= _vitalsHypotensionSystolic) {
      effectiveRedFlags['vitalsHypotension'] = true;
    }

    final hasRedFlag = _alwaysReferCategories.contains(symptomCategory) ||
        effectiveRedFlags.values.any((v) => v);
    final hasConsultationFlag = consultationFlags.values.any((v) => v);
    final result = hasRedFlag
        ? 'medical_referral'
        : (severityScore >= 4 || hasConsultationFlag ? 'consultation' : 'otc_suitable');
    return {
      'triageResult': result,
      'redFlagOverride': hasRedFlag,
      'explanation': 'AIプロキシに接続できないため簡易判定のみ表示しています。判定結果に従って対応し、薬剤師にご確認ください。',
      'tokenUsage': null,
    };
  }
}
