package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
)

// 推定トークン数(概算)。count_tokens 呼び出し前の粗い事前チェックに使う。
// 実際の消費量は Record() で APIレスポンスの実測値により補正される。
const estimatedTokensPerRequest = 1500

const triageSystemPrompt = "あなたは日本の薬剤師向けAIアシスタントです。施設スタッフが行ったOTCトリアージの内容について、" +
	"服薬指導・注意点を日本語で簡潔に説明してください。あなたは症状の診断や最終判定を行いません。" +
	"トリアージ区分はサーバー側の固定ロジックが既に決定しており、その結果を尊重した説明のみを行ってください。" +
	"レッドフラッグに該当する場合は、必ず医療機関受診が必要である旨を明記してください。"

// medicationMergeSystemPrompt は②医薬品注意点表示 B案でのみ使う、統合専用の制約付きプロンプト。
// LLMは新しい医学的判断を一切行わず、渡された添付文書の抜粋を整理・重複統合するだけに限定する。
const medicationMergeSystemPrompt = "あなたは日本の薬剤師向けアシスタントです。以下に渡す添付文書からの抜粋のみを根拠に、" +
	"複数薬剤にまたがる重複した注意点をまとめて整理してください。" +
	"抜粋に書かれていない情報は絶対に追加しないでください。各行に、どの薬剤由来かを必ず記載してください。" +
	"新しい医学的判断や推奨は一切行わず、渡された文章の要約・整理のみを行ってください。"

type server struct {
	claude          *ClaudeClient
	globalBudget    *TokenBudget
	facilityBudgets *FacilityTokenBudgets
	firestore       *FirestoreClient // nilの場合、薬剤知識ベース機能(②)は無効
}

// reserveBudgets は「施設単位の予算」と「全体の安全上限」の二層でトークン枠を確保する。
// 施設予算は公平性(1施設が全体を使い切って他施設をブロックしないため)、
// 全体予算は安全弁(想定外の請求膨張を防ぐ最終ライン)という役割分担。
// 全体側で拒否された場合、既に確保した施設側の枠は即座に解放する。
func (s *server) reserveBudgets(facilityID string, estimatedTokens int) (ok bool, remaining int) {
	facOK, facRemaining := s.facilityBudgets.Reserve(facilityID, estimatedTokens)
	if !facOK {
		return false, facRemaining
	}

	globalOK, globalRemaining := s.globalBudget.Reserve(estimatedTokens)
	if !globalOK {
		s.facilityBudgets.Record(facilityID, estimatedTokens, 0) // 未使用分を解放
		return false, globalRemaining
	}

	return true, min(facRemaining, globalRemaining)
}

// recordBudgets は実測トークン数で施設予算・全体予算の両方を補正する。
func (s *server) recordBudgets(facilityID string, estimated, actual int) {
	s.facilityBudgets.Record(facilityID, estimated, actual)
	s.globalBudget.Record(estimated, actual)
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, ErrorResponse{Error: message})
}

func buildTriagePrompt(req TriageRequest, triageResult string) string {
	symptoms := strings.Join(req.SymptomQualities, "、")
	medicines := "なし"
	if len(req.MedicineNames) > 0 {
		medicines = strings.Join(req.MedicineNames, "、")
	}

	return fmt.Sprintf(`症状カテゴリー: %s
具体的な症状: %s
重症度スコア: %d/5
サーバー判定結果: %s
服用中の薬剤: %s

上記のサーバー判定結果を前提として、施設スタッフ・薬剤師向けに以下を簡潔に説明してください（各項目2〜3行）:
1. この症状に関する一般的な注意点
2. 服用中の薬剤との関連で気をつけるべき点（該当する場合のみ）
3. 次に取るべきアクション（サーバー判定結果に沿った内容）`, req.SymptomCategory, symptoms, req.SeverityScore, triageResult, medicines)
}

func toTokenUsage(usage messagesUsage) TokenUsage {
	return TokenUsage{
		InputTokens:      usage.InputTokens,
		OutputTokens:     usage.OutputTokens,
		CacheReadTokens:  usage.CacheReadInputTokens,
		CacheWriteTokens: usage.CacheCreationInputTokens,
		EstimatedCostUSD: estimateCostUSD(usage),
	}
}

// analyzeMedicationHandler は ai_drug_service.dart の analyzeVisitMedicines と対応するエンドポイント。
// POST /v1/analyze-medication
//
// ②医薬品注意点表示 B案(根拠付き個別最適化)。LLMの自由生成は行わない:
//  1. 各薬剤名を一般名に名寄せ(MatchDrugName、失敗時はレビューキューへ)
//  2. 一般名から添付文書ナレッジ(drug_knowledge_base)を検索
//  3. 患者のeGFR/肝機能/年齢に基づき、表示すべきセクションを決定論的に選択(SelectCautionsForDrug)
//  4. 複数薬剤にまたがる重複がある場合のみ、LLMに整理を依頼(mergeCautionsWithLLM)。
//     1薬剤のみ、または重複がない場合はLLM呼び出し自体を省略する。
func (s *server) analyzeMedicationHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "POSTのみ対応しています")
		return
	}

	var req MedicationCautionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "リクエストボディが不正です")
		return
	}
	if len(req.MedicineNames) == 0 {
		writeError(w, http.StatusBadRequest, "medicineNames は必須です")
		return
	}
	if s.firestore == nil {
		writeError(w, http.StatusServiceUnavailable, "薬剤知識ベースが利用できません(GOOGLE_APPLICATION_CREDENTIALS未設定)")
		return
	}

	lookup := &firestoreDrugLookup{client: s.firestore}

	var results []DrugCautionResult
	var allCautions []SurfacedCaution

	for _, name := range req.MedicineNames {
		match, err := MatchDrugName(lookup, name)
		if err != nil {
			results = append(results, DrugCautionResult{InputName: name, Matched: false, Status: "error"})
			continue
		}
		if !match.Matched {
			results = append(results, DrugCautionResult{InputName: name, Matched: false, Status: "unmatched"})
			continue
		}

		entry, found, err := fetchKnowledgeEntry(s.firestore, match.GenericName)
		if err != nil || !found || entry.Status != "complete" {
			status := "pending_fetch"
			if found {
				status = entry.Status
			} else if err == nil {
				// drug_knowledge_baseに1件もエントリがない = 実際に患者が持っている薬剤で
				// 初めて需要が発生したケース。「取得待ちリスト」に記録し、後で管理画面から
				// 取得できるようにする(記録しないと、この需要はレスポンスを返した瞬間に消えてしまう)。
				recordFetchRequest(s.firestore, match.GenericName, name)
			}
			results = append(results, DrugCautionResult{
				InputName: name, Matched: true, GenericName: match.GenericName, Status: status,
			})
			continue
		}

		cautions := SelectCautionsForDrug(entry, req.EGFR, req.LiverStatus, req.Age)
		results = append(results, DrugCautionResult{
			InputName: name, Matched: true, GenericName: match.GenericName, Status: "complete", Cautions: cautions,
		})
		allCautions = append(allCautions, cautions...)
	}

	response := MedicationCautionResponse{Drugs: results}

	if needsMerge(allCautions) {
		summary, usage, err := s.mergeCautionsWithLLM(allCautions, req.FacilityID)
		if err != nil {
			response.MergedSummary = "統合表示は現在利用できません。薬剤ごとの詳細をご確認ください。"
		} else {
			response.MergedSummary = summary
			response.TokenUsage = toTokenUsage(usage)
		}
	}

	writeJSON(w, http.StatusOK, response)
}

// needsMerge はLLMによる重複統合が必要かを判定する。
// 注意点が2件未満、または全て同一薬剤由来ならLLM呼び出し自体が不要
// (実質的にAPIコストが発生するケースを最小限に絞る設計)。
func needsMerge(cautions []SurfacedCaution) bool {
	if len(cautions) < 2 {
		return false
	}
	drugs := map[string]bool{}
	for _, c := range cautions {
		drugs[c.GenericName] = true
	}
	return len(drugs) >= 2
}

func (s *server) mergeCautionsWithLLM(cautions []SurfacedCaution, facilityID string) (string, messagesUsage, error) {
	var b strings.Builder
	for _, c := range cautions {
		fmt.Fprintf(&b, "【%s】(%s)\n%s\n\n", c.GenericName, c.Reason, c.Text)
	}

	ok, remaining := s.reserveBudgets(facilityID, estimatedTokensPerRequest)
	if !ok {
		return "", messagesUsage{}, fmt.Errorf("トークン上限到達（残り%dトークン）", remaining)
	}

	text, usage, err := s.claude.SendMessage(medicationMergeSystemPrompt, b.String(), 600)
	if err != nil {
		s.recordBudgets(facilityID, estimatedTokensPerRequest, 0)
		return "", messagesUsage{}, err
	}
	s.recordBudgets(facilityID, estimatedTokensPerRequest, usage.InputTokens+usage.OutputTokens)
	return text, usage, nil
}

// triageHandler は OTCTriageFormScreen からのリクエストを処理する。
// POST /v1/triage
// トリアージ区分(TriageResult)はこのハンドラ内で DetermineTriageResult が決定し、
// AIの応答テキストによって上書きされることはない(安全弁ロジック)。
func (s *server) triageHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "POSTのみ対応しています")
		return
	}

	var req TriageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "リクエストボディが不正です")
		return
	}
	if len(req.SymptomQualities) == 0 {
		writeError(w, http.StatusBadRequest, "symptomQualities は必須です")
		return
	}

	// バイタル実測値(SpO2・血圧)があれば、自己申告チェックボックスを補完する形で
	// redFlagsに自動合成する(design_notes.mdの数値基準に対応)。
	req.RedFlags = ApplyVitalsRedFlags(req.SymptomCategory, req.RedFlags, req.SpO2, req.BPSystolic)

	// 安全弁: レッドフラッグ・重症度に基づく最終判定は必ずサーバー側で決定論的に行う。
	triageResult, redFlagOverride := DetermineTriageResult(req.SymptomCategory, req.RedFlags, req.ConsultationFlags, req.SeverityScore)

	userPrompt := buildTriagePrompt(req, triageResult)

	// 安全弁ロジック(DetermineTriageResult)の結果は、AI呼び出しの成否に関わらず必ず返す。
	// Claude API が利用不可(未契約・障害・上限到達)でも、トリアージ区分の判定自体は
	// サーバー側で完結しているため、この機能を止めてはならない。
	ok, remaining := s.reserveBudgets(req.FacilityID, estimatedTokensPerRequest)
	if !ok {
		writeJSON(w, http.StatusOK, TriageResponse{
			TriageResult:    triageResult,
			RedFlagOverride: redFlagOverride,
			Explanation:     fmt.Sprintf("AI解説は本日のトークン上限に達したため利用できません（残り %d トークン）。判定結果に従って対応してください。", remaining),
		})
		return
	}

	explanation, usage, err := s.claude.SendMessage(triageSystemPrompt, userPrompt, 600)
	if err != nil {
		// AI呼び出しが失敗しても、確保したトークン枠は使っていないので即座に返却する。
		s.recordBudgets(req.FacilityID, estimatedTokensPerRequest, 0)
		// 失敗の詳細は運用者向けにログへ出し、画面には出さない。
		// err には "ANTHROPIC_API_KEY が設定されていません" のような内部構成が
		// そのまま入るため、介護施設の職員に見せる文言に混ぜてはいけない。
		log.Printf("トリアージのAI解説生成に失敗: %v", err)
		writeJSON(w, http.StatusOK, TriageResponse{
			TriageResult:    triageResult,
			RedFlagOverride: redFlagOverride,
			Explanation:     "AI解説は現在利用できません。判定結果に従って対応し、必要に応じて薬剤師・医師に相談してください。",
		})
		return
	}

	s.recordBudgets(req.FacilityID, estimatedTokensPerRequest, usage.InputTokens+usage.OutputTokens)

	writeJSON(w, http.StatusOK, TriageResponse{
		TriageResult:    triageResult,
		RedFlagOverride: redFlagOverride,
		Explanation:     explanation,
		TokenUsage:      toTokenUsage(usage),
	})
}

// healthHandler はサーバー稼働状態と全体トークン予算の消費状況を返す。
// GET /healthz, GET /ping (Cloud Run本番では /ping を使うこと。main.goのコメント参照)
func (s *server) healthHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":            "ok",
		"globalBudget":      s.globalBudget.Status(),
		"trackedFacilities": fmt.Sprintf("%d", s.facilityBudgets.FacilityCount()),
	})
}
