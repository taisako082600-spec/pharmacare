package main

// alwaysReferCategories は、そのカテゴリが選択された時点で無条件に医療機関受診を
// 推奨するsymptomCategory。書籍「アルゴリズムで考える 薬剤師の臨床判断」の意識障害
// アルゴリズムが「急性発症+神経症状＝即救急要請」と明文化しているのと同様、
// このアプリの3段階判定(medical_referral/consultation/otc_suitable)のうち
// otc_suitableに該当する意識障害の症例は実質存在しないため、個別のレッドフラッグ
// チェックボックスの状態によらずカテゴリ選択自体をレッドフラッグ相当として扱う
// (2026-07-20、15症候別レッドフラッグへの拡張時に追加)。
var alwaysReferCategories = map[string]bool{
	"consciousness": true,
}

// DetermineTriageResult は Flutter 側 otc_triage_form_screen.dart の
// _determineTriageResult と同一ロジックをGo側に複製したもの。
//
// AIが生成する説明文の内容に関わらず、トリアージ区分の最終判定は必ずこの関数が行う。
// レッドフラッグサインが1つでも該当すれば、重症度スコアの値によらず医療機関受診推奨とする
// (安全側に倒す設計。詳細は OTC_TRIAGE_FEATURE.md の「制約・注意点」参照)。
//
// consultationFlags は redFlags より一段弱い「受診勧奨」相当のサイン
// (例: 風邪の「症状が1つだけ突出」= 単一臓器への細菌感染の可能性。書籍2の核心ルール)。
// redFlags のような即時受診推奨(medical_referral)ではなく、consultation止まりとする
// ことで、緊急度の低いサインを過度に赤色警告してしまう誤った重症度表示を避ける
// (2026-07-20、oneSymptomDominantをredFlagsから分離した際に導入)。
func DetermineTriageResult(symptomCategory string, redFlags map[string]bool, consultationFlags map[string]bool, severityScore int) (result string, redFlagOverride bool) {
	if alwaysReferCategories[symptomCategory] {
		return "medical_referral", true
	}

	for _, checked := range redFlags {
		if checked {
			return "medical_referral", true
		}
	}

	if severityScore >= 4 {
		return "consultation", false
	}

	for _, checked := range consultationFlags {
		if checked {
			return "consultation", false
		}
	}

	return "otc_suitable", false
}

// バイタル実測値は、チェックボックスでの自己申告に頼らず自動的にredFlags相当の
// サインとして扱う。
//
//   - SpO2 90%未満:      低酸素血症。カテゴリを問わない
//   - 収縮期血圧 180以上: headacheカテゴリのみ。高血圧脳症を疑う
//   - 収縮期血圧 100以下: カテゴリを問わない。ショック/qSOFA項目
//
// 低血圧のしきい値100mmHgは、書籍1『アルゴリズムで考える 薬剤師の臨床判断』発熱章が
// 敗血症のスクリーニングとして挙げるqSOFA(収縮期血圧≦100mmHg・呼吸数>22回/分・
// 意識変容のうち2項目以上)に由来する。同書では「ショック」が発熱・腹痛・腰痛・下痢・
// 意識障害など多くの症候で「見逃してはいけない緊急性の高い疾患」の徴候として繰り返し
// 挙げられているため、本アプリでは2項目を待たず収縮期血圧単独でも危険信号として扱う
// (トリアージは安全側に倒す)。
const (
	vitalsLowSpO2Threshold           = 90.0
	vitalsSevereHypertensionSystolic = 180.0
	vitalsHypotensionSystolic        = 100.0
)

// ApplyVitalsRedFlags はバイタル実測値(SpO2・収縮期血圧)から自動的にredFlagsへ合成する。
// 呼び出し側は DetermineTriageResult を呼ぶ前にこれを適用すること。
func ApplyVitalsRedFlags(symptomCategory string, redFlags map[string]bool, spo2 *float64, bpSystolic *float64) map[string]bool {
	if redFlags == nil {
		redFlags = map[string]bool{}
	}
	if spo2 != nil && *spo2 < vitalsLowSpO2Threshold {
		redFlags["vitalsLowSpO2"] = true
	}
	if bpSystolic != nil && *bpSystolic >= vitalsSevereHypertensionSystolic && symptomCategory == "headache" {
		redFlags["vitalsSevereHypertension"] = true
	}
	if bpSystolic != nil && *bpSystolic <= vitalsHypotensionSystolic {
		redFlags["vitalsHypotension"] = true
	}
	return redFlags
}
