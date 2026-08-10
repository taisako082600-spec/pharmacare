package main

import (
	"os"
	"strings"
	"testing"
)

// TestVerifySavedKnowledgeBase は fetch-drug-label.exe "ロキソニン錠60mg" 実行後、
// 実際にFirestoreへ保存された内容を読み戻して検証する。
func TestVerifySavedKnowledgeBase(t *testing.T) {
	if os.Getenv("GOOGLE_APPLICATION_CREDENTIALS") == "" {
		t.Skip("GOOGLE_APPLICATION_CREDENTIALS 未設定のためスキップ")
	}

	client, err := NewFirestoreClient()
	if err != nil || client == nil {
		t.Skip("Firestoreクライアントを初期化できないためスキップ")
	}

	fields, found, err := client.GetDocument("drug_knowledge_base", "ロキソニン錠60mg")
	if err != nil {
		t.Fatalf("読み込み失敗: %v", err)
	}
	if !found {
		t.Fatal("drug_knowledge_base/ロキソニン錠60mg が見つかりません(先にfetch-drug-labelを実行してください)")
	}

	if fields["status"] != "complete" {
		t.Errorf("got status %v, want complete", fields["status"])
	}

	sections, ok := fields["sections"].(map[string]interface{})
	if !ok {
		t.Fatal("sections フィールドが正しく保存されていません")
	}

	renal, ok := sections["renal_impairment"].(map[string]interface{})
	if !ok {
		t.Fatal("renal_impairment セクションが保存されていません")
	}
	renalText, _ := renal["text"].(string)
	if !strings.Contains(renalText, "急性腎障害") {
		t.Errorf("保存された腎機能セクションの内容が想定と異なる: %q", renalText)
	}

	t.Logf("✅ Firestoreに実際に保存された内容を確認: sourceUrl=%v, formatVersion=%v, セクション数=%d",
		fields["sourceUrl"], fields["formatVersion"], len(sections))
}
