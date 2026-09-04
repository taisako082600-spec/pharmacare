package main

import (
	"encoding/json"
	"net/http"
	"strings"
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

	// **一般名で先に引く**。販売名は補助。
	//
	// 以前は「PMDA検索は一般名より販売名の方がヒットしやすい」という前提で
	// 販売名だけを使っていたが、逆だった。実測(pmda_live_probe_test.go)では
	//   「クラリスロマイシン錠２００ｍｇ「大正」」 → 該当なし
	//   「クラリスロマイシン錠200mg「大正」」    → 該当なし(全角/半角の問題ではない)
	//   「クラリスロマイシン」                     → 該当あり
	// で、販売名しか試さなかったために5回失敗し、手動登録待ちに積まれていた。
	// 手帳に書かれる販売名の表記はメーカーごとにぶれる一方、一般名は安定している。
	//
	// 販売名を捨てないのは、一般名の解決に失敗した薬剤が販売名のまま
	// genericName に入っていることがあるため(例: drug_knowledge_base の
	// 「ロキソニン錠60mg」)。その場合は販売名側でしか引けない。
	html, sourceURL, fetchErr := FetchAttachmentDocument(req.GenericName)
	if fetchErr != nil && searchName != req.GenericName {
		if html2, sourceURL2, err2 := FetchAttachmentDocument(searchName); err2 == nil {
			html, sourceURL, fetchErr = html2, sourceURL2, nil
		}
	}
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

// adminParseLabelTextRequest は管理画面の手動登録で、添付文書PDFから
// ブラウザ側(pdf.js)が抜き出したプレーンテキストを受け取る。
//
// PDFそのものはサーバーへ送らない。抽出はブラウザ内で完結させ、ここへ来るのは
// テキストだけにしてある。医療情報の移動範囲を最小にするためと、
// プロキシを標準ライブラリのみで保つため(PDF解析ライブラリを足さずに済む)。
type adminParseLabelTextRequest struct {
	Text string `json:"text"`
}

// adminParseLabelTextHandler は添付文書のプレーンテキストを章立てに分割して返す。
// POST /v1/admin/parse-label-text (管理者専用)
//
// これまで手動登録は、管理者が5つの入力欄へPDFから章を1つずつ手で貼り付ける形だった。
// 分割そのものは自動取得側と同じ ChunkAttachmentDocument で済むので、それを
// 手動経路からも呼べるようにする。自動と手動で分割ロジックが分岐しないことが重要
// —— 同じ添付文書から取り込み経路によって別の結果が出るのは避けたい。
//
// **保存はしない**。返すのは分割結果だけで、Firestoreへ書くかどうかは
// 管理者が画面で中身を確認してから決める。抽出の取りこぼしや誤検出が
// そのまま保存されると、後段の注意点表示が黙って間違う。
func (s *server) adminParseLabelTextHandler(w http.ResponseWriter, r *http.Request) {
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

	var req adminParseLabelTextRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Text) == "" {
		writeError(w, http.StatusBadRequest, "text は必須です")
		return
	}

	sections, formatVersion := ChunkAttachmentDocument(req.Text)

	sectionsField := make(map[string]interface{}, len(sections))
	for category, section := range sections {
		sectionsField[category] = map[string]interface{}{
			"sectionNumber": section.SectionNumber,
			"sectionTitle":  section.SectionTitle,
			"text":          section.Text,
		}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"success":       len(sections) > 0,
		"formatVersion": formatVersion,
		"sections":      sectionsField,
	})
}
