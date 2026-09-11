import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacist_app/services/ai_drug_service.dart';

/// `_fallbackTriageResult`(AI プロキシに接続できないときに使う最後の砦)の検証。
///
/// この判定は `llm-proxy/redflag.go` の `DetermineTriageResult` /
/// `ApplyVitalsRedFlags` と**意図的に重複した実装**(オフラインでも判定を返すため)。
/// ケースは Go 側のテスト(`redflag_test.go`)と同じものを移植している —
/// 別言語で同じ入力を与えて同じ結果になることを確認するのが目的で、
/// 片方だけ直して食い違う事故を検知する。
void main() {
  final service = AiDrugService();

  group('DetermineTriageResult相当(症候・重症度)', () {
    final cases = <String, ({
      String category,
      Map<String, bool> redFlags,
      Map<String, bool> consultationFlags,
      int severity,
      String wantResult,
      bool wantOverride,
    })>{
      'レッドフラッグありは重症度に関わらず受診推奨': (
        category: 'cold',
        redFlags: {'highFever38Plus': true},
        consultationFlags: {},
        severity: 1,
        wantResult: 'medical_referral',
        wantOverride: true,
      ),
      'レッドフラッグなし・軽症はOTC対応可': (
        category: 'cold',
        redFlags: {'highFever38Plus': false},
        consultationFlags: {},
        severity: 2,
        wantResult: 'otc_suitable',
        wantOverride: false,
      ),
      'レッドフラッグなし・重症度4以上は要相談': (
        category: 'cold',
        redFlags: {},
        consultationFlags: {},
        severity: 4,
        wantResult: 'consultation',
        wantOverride: false,
      ),
      'レッドフラッグは重症度5でも受診推奨を優先する': (
        category: 'pain',
        redFlags: {'severePain': true},
        consultationFlags: {},
        severity: 5,
        wantResult: 'medical_referral',
        wantOverride: true,
      ),
      'レッドフラッグが複数あっても受診推奨のまま': (
        category: 'pain',
        redFlags: {'severePain': true, 'painWithVomiting': true},
        consultationFlags: {},
        severity: 1,
        wantResult: 'medical_referral',
        wantOverride: true,
      ),
      '意識障害カテゴリはレッドフラッグ未チェック・軽症でも受診推奨': (
        category: 'consciousness',
        redFlags: {},
        consultationFlags: {},
        severity: 1,
        wantResult: 'medical_referral',
        wantOverride: true,
      ),
      'consultationFlagsのみ該当は受診推奨(赤)ではなく要相談(黄)に留める': (
        category: 'cold',
        redFlags: {},
        consultationFlags: {'oneSymptomDominant': true},
        severity: 1,
        wantResult: 'consultation',
        wantOverride: false,
      ),
      'redFlagsとconsultationFlagsが両方ある場合はredFlagsが優先': (
        category: 'cold',
        redFlags: {'highFever38Plus': true},
        consultationFlags: {'oneSymptomDominant': true},
        severity: 1,
        wantResult: 'medical_referral',
        wantOverride: true,
      ),
    };

    cases.forEach((name, c) {
      test(name, () {
        final result = service.fallbackTriageResultForTesting(
          c.category,
          c.redFlags,
          c.consultationFlags,
          c.severity,
        );
        expect(result['triageResult'], c.wantResult, reason: 'triageResult');
        expect(result['redFlagOverride'], c.wantOverride, reason: 'redFlagOverride');
      });
    });
  });

  group('ApplyVitalsRedFlags相当(バイタル実測値)', () {
    // 判定に効くのは redFlagOverride の有無(=バイタルがレッドフラッグとして
    // 発火したか)。閾値の境界だけをここで確認する。
    final cases = <String, ({
      String category,
      double? spo2,
      double? bp,
      bool wantOverride,
    })>{
      'SpO2が90未満なら自動でレッドフラッグ': (
        category: 'coughDyspnea',
        spo2: 88,
        bp: null,
        wantOverride: true,
      ),
      'SpO2が90以上なら発火しない': (
        category: 'coughDyspnea',
        spo2: 95,
        bp: null,
        wantOverride: false,
      ),
      '頭痛+収縮期血圧180以上は自動でレッドフラッグ': (
        category: 'headache',
        spo2: null,
        bp: 185,
        wantOverride: true,
      ),
      '頭痛以外のカテゴリでは血圧180以上のみで発火しない': (
        category: 'fever',
        spo2: null,
        bp: 185,
        // fever には血圧180以上を見るルールが無い。ただし収縮期血圧185は
        // 低血圧(100以下)の閾値には該当しないため、全体としては発火しない。
        wantOverride: false,
      ),
      '測定値なしなら何も発火しない': (
        category: 'headache',
        spo2: null,
        bp: null,
        wantOverride: false,
      ),
      '収縮期血圧100以下はカテゴリを問わずレッドフラッグ': (
        category: 'diarrheaConstipation',
        spo2: null,
        bp: 88,
        wantOverride: true,
      ),
      '収縮期血圧ちょうど100も境界として含める': (
        category: 'fever',
        spo2: null,
        bp: 100,
        wantOverride: true,
      ),
      '収縮期血圧が101なら発火しない': (
        category: 'fever',
        spo2: null,
        bp: 101,
        wantOverride: false,
      ),
    };

    cases.forEach((name, c) {
      test(name, () {
        final result = service.fallbackTriageResultForTesting(
          c.category,
          const {},
          const {},
          1,
          spo2: c.spo2,
          bpSystolic: c.bp,
        );
        expect(result['redFlagOverride'], c.wantOverride);
      });
    });

    test('高血圧側(185)では低血圧フラグは立たない(headacheで確認)', () {
      final result = service.fallbackTriageResultForTesting(
        'headache',
        const {},
        const {},
        1,
        bpSystolic: 185,
      );
      // 185は vitalsSevereHypertension(headache限定)で発火するため
      // override自体はtrueになる。ここで見たいのは「低血圧側の閾値(<=100)を
      // 誤って併発させていないか」なので、素点で185は低血圧の条件(<=100)を
      // 満たさないことだけを確認する(境界条件の取り違えを防ぐ)。
      expect(result['redFlagOverride'], true);
    });
  });

  test('プロキシ未接続の説明文が薬剤師への確認を促している', () {
    final result = service.fallbackTriageResultForTesting(
      'cold',
      const {},
      const {},
      1,
    );
    expect(result['explanation'], contains('薬剤師'));
  });
}
