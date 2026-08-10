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

// vitalsLowSpO2Threshold未満のSpO2、またはheadacheカテゴリでのvitalsSevereHypertensionThreshold
// 以上の収縮期血圧は、チェックボックスでの自己申告に頼らずバイタル実測値から自動的に
// redFlags相当のサインとして扱う(design_notes.mdの「SpO2 90%未満」「拍動性頭痛+高度高血圧」に対応)。
const (
	vitalsLowSpO2Threshold           = 90.0
	vitalsSevereHypertensionSystolic = 180.0
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
	return redFlags
}
