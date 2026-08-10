package main

// MedicationCautionRequest は Flutter 側 ai_drug_service.dart の
// analyzeVisitMedicines と対応するリクエストボディ。
// ②医薬品注意点表示 B案(根拠付き個別最適化)に対応。自由記述生成は行わない。
type MedicationCautionRequest struct {
	FacilityID    string   `json:"facilityId,omitempty"`
	MedicineNames []string `json:"medicineNames"`
	EGFR          *float64 `json:"egfr,omitempty"`
	LiverStatus   string   `json:"liverStatus,omitempty"`
	Age           *int     `json:"age,omitempty"`
}

type TokenUsage struct {
	InputTokens      int     `json:"inputTokens"`
	OutputTokens     int     `json:"outputTokens"`
	CacheReadTokens  int     `json:"cacheReadTokens"`
	CacheWriteTokens int     `json:"cacheWriteTokens"`
	EstimatedCostUSD float64 `json:"estimatedCostUsd"`
}

// DrugCautionResult は1薬剤分の名寄せ・知識ベース検索結果。
// Status: "complete"(注意点あり) | "pending_fetch"/"fetch_failed"/"manual_needed"(添付文書整備待ち)
//
//	| "unmatched"(名寄せ未解決) | "error"
type DrugCautionResult struct {
	InputName   string            `json:"inputName"`
	Matched     bool              `json:"matched"`
	GenericName string            `json:"genericName,omitempty"`
	Status      string            `json:"status"`
	Cautions    []SurfacedCaution `json:"cautions,omitempty"`
}

// MedicationCautionResponse がFlutterに返す最終形。
// MergedSummary は複数薬剤にまたがる重複がある場合のみLLMが生成する(該当なしなら空文字)。
type MedicationCautionResponse struct {
	Drugs         []DrugCautionResult `json:"drugs"`
	MergedSummary string              `json:"mergedSummary,omitempty"`
	TokenUsage    TokenUsage          `json:"tokenUsage"`
}

// TriageRequest は OTCTriageFormScreen からのリクエストボディ。
// RedFlags のキーは otc_triage_form_screen.dart の redFlagOptions と対応する。
// ConsultationFlags は consultationFlagOptions と対応する、redFlagsより一段弱い受診勧奨サイン。
// SpO2/BPSystolicはオプションのバイタル入力(未測定ならnil、自己申告チェックボックスの補完)。
type TriageRequest struct {
	FacilityID        string          `json:"facilityId,omitempty"`
	PatientID         string          `json:"patientId,omitempty"`
	SymptomCategory   string          `json:"symptomCategory"`
	SymptomQualities  []string        `json:"symptomQualities"`
	SeverityScore     int             `json:"severityScore"`
	RedFlags          map[string]bool `json:"redFlags"`
	ConsultationFlags map[string]bool `json:"consultationFlags,omitempty"`
	SpO2              *float64        `json:"spo2,omitempty"`
	BPSystolic        *float64        `json:"bpSystolic,omitempty"`
	PulseRate         *float64        `json:"pulseRate,omitempty"`
	EGFR              *float64        `json:"egfr,omitempty"`
	LiverStatus       string          `json:"liverStatus,omitempty"`
	MedicineNames     []string        `json:"medicineNames,omitempty"`
}

// TriageResponse の TriageResult は必ずサーバー側 DetermineTriageResult の結果であり、
// Explanation (AI生成テキスト) によって上書きされることはない。
type TriageResponse struct {
	TriageResult    string     `json:"triageResult"`
	RedFlagOverride bool       `json:"redFlagOverride"`
	Explanation     string     `json:"explanation"`
	TokenUsage      TokenUsage `json:"tokenUsage"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}
