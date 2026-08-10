package main

import "fmt"

// DrugKnowledgeSection は添付文書から抽出された1セクション(9.2 腎機能障害患者 等)。
type DrugKnowledgeSection struct {
	SectionNumber string `json:"sectionNumber"`
	SectionTitle  string `json:"sectionTitle"`
	Text          string `json:"text"`
}

// DrugKnowledgeEntry は一般名1件分の知識ベースエントリ(drug_knowledge_base/{一般名})。
type DrugKnowledgeEntry struct {
	GenericName string                          `json:"genericName"`
	Status      string                          `json:"status"` // "complete" | "pending_fetch" | "fetch_failed" | "manual_needed"
	Sections    map[string]DrugKnowledgeSection `json:"sections"`
}

func formatEGFRReason(egfr float64) string {
	status := "要注意"
	if egfr < 30 {
		status = "低下"
	}
	return fmt.Sprintf("eGFR %.1f（%s）のため表示", egfr, status)
}

func formatAgeReason(age int) string {
	return fmt.Sprintf("%d歳（高齢者）のため表示", age)
}

// renalNormalThresholdEGFR は ai_drug_service.dart で使われている「正常/要注意/低下」の
// 閾値(eGFR 60)と揃えている。腎機能障害患者向けセクションを表示するかどうかの判定に使う。
const renalNormalThresholdEGFR = 60.0

// elderlyAgeThreshold は添付文書の「高齢者」セクションを表示する年齢の目安。
// 添付文書自体に明確な年齢定義がないことが多いため、一般的な高齢者の目安(65歳)を採用する。
const elderlyAgeThreshold = 65

// ReducedRenalFunction はeGFRが正常範囲を下回っているかを判定する。
func ReducedRenalFunction(egfr *float64) bool {
	return egfr != nil && *egfr < renalNormalThresholdEGFR
}

// AbnormalLiverFunction は肝機能ステータスが「正常」でないかを判定する。
func AbnormalLiverFunction(liverStatus string) bool {
	return liverStatus != "" && liverStatus != "正常"
}

// IsElderly は年齢が高齢者の目安を超えているかを判定する。
func IsElderly(age *int) bool {
	return age != nil && *age >= elderlyAgeThreshold
}

// ShouldSurfaceSection は、添付文書の1セクションを患者向けに表示すべきかを決定論的に判定する。
// LLMは一切関与しない。判定は「セクションに実際の記載があるか」と「患者の実際の値が
// そのセクションの対象状態に該当するか」の2条件のANDのみで決まる(医薬品注意点表示 B案の中核ロジック)。
//
// 添付文書側の数値閾値(例:「eGFR30未満で減量」)を解釈することはしない。
// セクションが存在し、かつ患者の状態が一般的な異常域にあれば、その文章をそのまま提示するだけに留める。
func ShouldSurfaceSection(category string, sectionText string, egfr *float64, liverStatus string, age *int) bool {
	if sectionText == "" {
		return false
	}

	switch category {
	case "renal_impairment":
		return ReducedRenalFunction(egfr)
	case "hepatic_impairment":
		return AbnormalLiverFunction(liverStatus)
	case "elderly":
		return IsElderly(age)
	default:
		// 重大な副作用等、患者の個別値に依存しないカテゴリは無条件表示
		return true
	}
}

// SurfacedCaution は表示すべきと判定された1件の注意点。
type SurfacedCaution struct {
	GenericName   string `json:"genericName"`
	Category      string `json:"category"`
	SectionNumber string `json:"sectionNumber"`
	Text          string `json:"text"`
	Reason        string `json:"reason"` // 表示理由(利用者への説明用。例: "eGFR 45（要注意）のため表示")
}

// SelectCautionsForDrug は1薬剤分の知識ベースエントリから、この患者に表示すべき
// 注意点だけを機械的に抽出する。
func SelectCautionsForDrug(entry DrugKnowledgeEntry, egfr *float64, liverStatus string, age *int) []SurfacedCaution {
	var out []SurfacedCaution
	for category, section := range entry.Sections {
		if !ShouldSurfaceSection(category, section.Text, egfr, liverStatus, age) {
			continue
		}
		out = append(out, SurfacedCaution{
			GenericName:   entry.GenericName,
			Category:      category,
			SectionNumber: section.SectionNumber,
			Text:          section.Text,
			Reason:        surfaceReason(category, egfr, liverStatus, age),
		})
	}
	return out
}

func surfaceReason(category string, egfr *float64, liverStatus string, age *int) string {
	switch category {
	case "renal_impairment":
		if egfr != nil {
			return formatEGFRReason(*egfr)
		}
		return "腎機能低下のため表示"
	case "hepatic_impairment":
		return "肝機能: " + liverStatus + " のため表示"
	case "elderly":
		if age != nil {
			return formatAgeReason(*age)
		}
		return "高齢者に該当するため表示"
	default:
		return "添付文書の記載事項として表示"
	}
}
