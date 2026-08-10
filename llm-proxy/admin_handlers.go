package main

import (
	"encoding/json"
	"net/http"
	"time"
)

// adminFetchDrugLabelRequest は管理画面「取得待ちリスト」タブの「取得実行」ボタンから送られる。
// searchName は省略可(省略時は genericName でPMDA検索する)。実運用では
// drug_fetch_requests.exampleInputNames の1件(実際に患者手帳へ入力された商品名)を渡すことが多い
// —— PMDA検索は薬理学的な一般名より販売名(商品名)の方がヒットしやすいため。
type adminFetchDrugLabelRequest struct {
	GenericName string `json:"genericName"`
	SearchName  string `json:"searchName,omitempty"`
}

// adminFetchDrugLabelHandler は管理画面から直接PMDA添付文書の自動取得を実行する。
// POST /v1/admin/fetch-drug-label (管理者専用)
//
// これまで fetch-drug-label.exe をterminalから手動実行する以外に取得手段がなかった
// (main.goのコメントどおり「taiさんが手動実行するバッチツール」)。このエンドポイントは
// 同じ取得ロジック(pmda_fetch.go / pmda_html_extract.go / chunk.go、fetch-drug-labelと同期)を
// Web管理画面のボタン一つから実行できるようにする。
func (s *server) adminFetchDrugLabelHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "POSTのみ対応しています")
		return
	}
	if s.firestore == nil {
		writeError(w, http.StatusServiceUnavailable, "Firestoreが利用できません(GOOGLE_APPLICATION_CREDENTIALS未設定)")
		return
	}

	uid, _ := r.Context().Value(uidContextKey).(string)
	admin, err := isAdminUser(s.firestore, uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "権限確認に失敗しました: "+err.Error())
		return
	}
	if !admin {
		writeError(w, http.StatusForbidden, "管理者権限が必要です")
		return
	}

	var req adminFetchDrugLabelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.GenericName == "" {
		writeError(w, http.StatusBadRequest, "genericName は必須です")
		return
	}
	searchName := req.SearchName
	if searchName == "" {
		searchName = req.GenericName
	}

	html, sourceURL, fetchErr := FetchAttachmentDocument(searchName)
	if fetchErr != nil {
		recordManualNeeded(s.firestore, req.GenericName, "", "", fetchErr.Error())
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false, "reason": fetchErr.Error(),
		})
		return
	}

	// PMDA(info.pmda.go.jp)の実HTMLはセマンティックIDを持つため、まずそちらを優先して試す。
	// 抽出できなければ、数字見出しベースのフォールバック(旧様式・非PMDA由来のテキスト向け)を試す。
	formatVersion := "new"
	sections := ExtractPMDASections(html)
	if len(sections) == 0 {
		sections, formatVersion = ChunkAttachmentDocument(html)
	}
	if len(sections) == 0 {
		recordManualNeeded(s.firestore, req.GenericName, formatVersion, sourceURL, "セクション抽出0件")
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false, "reason": "セクションが1件も抽出できませんでした",
		})
		return
	}

	sectionsField := make(map[string]interface{}, len(sections))
	for category, section := range sections {
		sectionsField[category] = map[string]interface{}{
			"sectionNumber": section.SectionNumber,
			"sectionTitle":  section.SectionTitle,
			"text":          section.Text,
		}
	}

	err = s.firestore.SetDocument("drug_knowledge_base", req.GenericName, map[string]interface{}{
		"genericName":   req.GenericName,
		"status":        "complete",
		"formatVersion": formatVersion,
		"sourceUrl":     sourceURL,
		"fetchedAt":     time.Now(),
		"sections":      sectionsField,
		"updatedAt":     time.Now(),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Firestoreへの保存に失敗しました: "+err.Error())
		return
	}

	clearFetchRequest(s.firestore, req.GenericName)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"success":       true,
		"sectionCount":  len(sections),
		"formatVersion": formatVersion,
		"sourceUrl":     sourceURL,
	})
}
