package main

import "time"

// drug_fetch_requests は、名寄せ(MatchDrugName)には成功したが drug_knowledge_base に
// エントリが1件も存在しない薬剤の「実需要」を記録するコレクション。
//
// analyzeMedicationHandler が返す status:"pending_fetch" は従来レスポンスに含まれるだけで
// Firestoreには何も残らず、患者が実際に登録した薬剤のうちどれが未整備なのか後から
// 分からなくなっていた。このファイルはその需要を永続化し、管理画面の
// 「取得待ちリスト」タブ・/v1/admin/fetch-drug-label で使う
// (medication_caution_b_plan_design.md の「インクリメンタル型RAG」方針を実現する仕組み)。

// recordFetchRequest は drug_fetch_requests/{genericName} を作成/更新する。
// 書き込み失敗はログ用途を止めるほどの重大性はないため、エラーは呼び出し元に伝播しない
// (analyzeMedicationHandler 本来の応答を遅延・失敗させないため)。
func recordFetchRequest(client *FirestoreClient, genericName, rawInput string) {
	existing, found, err := client.GetDocument("drug_fetch_requests", genericName)
	if err == nil && found {
		if status, _ := existing["status"].(string); status == "fetched" {
			return // 既に整備済みなら記録不要
		}
	}

	now := time.Now()
	var exampleInputs []string
	var requestCount int64 = 1
	firstRequestedAt := interface{}(now)

	if found {
		if names, ok := existing["exampleInputNames"].([]interface{}); ok {
			for _, n := range names {
				if s, ok := n.(string); ok {
					exampleInputs = append(exampleInputs, s)
				}
			}
		}
		if c, ok := existing["requestCount"].(int64); ok {
			requestCount = c + 1
		}
		if t, ok := existing["firstRequestedAt"]; ok {
			firstRequestedAt = t
		}
	}

	alreadyKnown := false
	for _, s := range exampleInputs {
		if s == rawInput {
			alreadyKnown = true
			break
		}
	}
	if !alreadyKnown && len(exampleInputs) < 5 {
		exampleInputs = append(exampleInputs, rawInput)
	}

	_ = client.SetDocument("drug_fetch_requests", genericName, map[string]interface{}{
		"genericName":       genericName,
		"exampleInputNames": exampleInputs,
		"requestCount":      requestCount,
		"status":            "pending",
		"firstRequestedAt":  firstRequestedAt,
		"lastRequestedAt":   now,
	})
}

// clearFetchRequest は取得が完了した薬剤を「取得待ちリスト」から消す。
// ドキュメントが存在しなくてもエラーにしない(DeleteDocumentの既存挙動どおり)。
func clearFetchRequest(client *FirestoreClient, genericName string) {
	_ = client.DeleteDocument("drug_fetch_requests", genericName)
}

// isAdminUser は users/{uid}.isAdmin を見て管理者かどうかを判定する。
// firestore.rules の isAdmin() ヘルパーと同じ判定条件をサーバー側でも複製している
// (Flutter管理画面と同じ「isAdminフィールド」を権威とするため)。
func isAdminUser(client *FirestoreClient, uid string) (bool, error) {
	if uid == "" {
		return false, nil
	}
	fields, found, err := client.GetDocument("users", uid)
	if err != nil || !found {
		return false, err
	}
	isAdmin, _ := fields["isAdmin"].(bool)
	return isAdmin, nil
}

// recordManualNeeded は自動取得に失敗した薬剤を drug_knowledge_base に
// status:"manual_needed" として記録する(fetch-drug-label/main.go の同名関数と同一ロジック、
// 管理画面からの直接取得のためllm-proxy側にも複製)。
func recordManualNeeded(client *FirestoreClient, genericName, formatVersion, sourceURL, reason string) {
	existing, found, _ := client.GetDocument("drug_knowledge_base", genericName)
	var attempts int64 = 1
	if found {
		if a, ok := existing["fetchAttempts"].(int64); ok {
			attempts = a + 1
		}
	}

	_ = client.SetDocument("drug_knowledge_base", genericName, map[string]interface{}{
		"genericName":    genericName,
		"status":         "manual_needed",
		"formatVersion":  formatVersion,
		"sourceUrl":      sourceURL,
		"fetchAttempts":  attempts,
		"lastFetchError": reason,
		"updatedAt":      time.Now(),
	})
}
