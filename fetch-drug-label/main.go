package main

import (
	"fmt"
	"os"
	"time"
)

// fetch-drug-label は taiさんが手動実行するバッチツール(deploy_firestore.jsと同じ位置づけ)。
// 実際のユーザーリクエストの中では絶対に実行しない重い処理を、ここに切り離している。
//
// Usage:
//
//	fetch-drug-label import-master        薬価基準収載品目リストをdrug_masterへ一括取り込み
//	fetch-drug-label <一般名>              添付文書を取得・チャンク化してdrug_knowledge_baseへ保存
func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	if os.Args[1] == "import-master" {
		RunImportDrugMaster()
		return
	}

	runFetchLabel(os.Args[1])
}

func printUsage() {
	fmt.Println("Usage:")
	fmt.Println("  fetch-drug-label import-master   薬価基準収載品目リストをdrug_masterへ一括取り込み")
	fmt.Println("  fetch-drug-label <一般名>         添付文書を取得・チャンク化してdrug_knowledge_baseへ保存")
}

func runFetchLabel(genericName string) {
	client, err := NewFirestoreClient()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Firestore初期化エラー: %v\n", err)
		os.Exit(1)
	}
	if client == nil {
		fmt.Fprintln(os.Stderr, "GOOGLE_APPLICATION_CREDENTIALS が未設定です")
		os.Exit(1)
	}

	fmt.Printf("「%s」の添付文書取得を試みます...\n", genericName)

	html, sourceURL, fetchErr := FetchAttachmentDocument(genericName)
	if fetchErr != nil {
		fmt.Printf("取得失敗: %v\n", fetchErr)
		fmt.Println("→ manual_needed として記録します(管理画面での手動整備待ち)")
		recordManualNeeded(client, genericName, "", "", fetchErr.Error())
		os.Exit(1)
	}

	// PMDA(info.pmda.go.jp)の実HTMLはセマンティックIDを持つため、まずそちらを優先して試す。
	// 抽出できなければ、数字見出しベースのフォールバック(旧様式・非PMDA由来のテキスト向け)を試す。
	formatVersion := "new"
	sections := ExtractPMDASections(html)
	if len(sections) == 0 {
		sections, formatVersion = ChunkAttachmentDocument(html)
	}
	if len(sections) == 0 {
		fmt.Println("警告: セクションが1件も抽出できませんでした")
		recordManualNeeded(client, genericName, formatVersion, sourceURL, "セクション抽出0件")
		os.Exit(1)
	}

	sectionsField := make(map[string]interface{}, len(sections))
	for category, section := range sections {
		sectionsField[category] = map[string]interface{}{
			"sectionNumber": section.SectionNumber,
			"sectionTitle":  section.SectionTitle,
			"text":          section.Text,
		}
	}

	err = client.SetDocument("drug_knowledge_base", genericName, map[string]interface{}{
		"genericName":   genericName,
		"status":        "complete",
		"formatVersion": formatVersion,
		"sourceUrl":     sourceURL,
		"fetchedAt":     time.Now(),
		"sections":      sectionsField,
		"updatedAt":     time.Now(),
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Firestoreへの保存に失敗しました: %v\n", err)
		os.Exit(1)
	}

	// 取得待ちリスト(drug_fetch_requests)に同名のエントリがあれば消す。
	// 存在しなくてもエラーにならない(DeleteDocumentの既存挙動どおり)。
	if delErr := client.DeleteDocument("drug_fetch_requests", genericName); delErr != nil {
		fmt.Fprintf(os.Stderr, "警告: 取得待ちリストの削除に失敗しました: %v\n", delErr)
	}

	fmt.Printf("✅ %d件のセクションを保存しました(様式: %s)\n", len(sections), formatVersion)
}

func recordManualNeeded(client *FirestoreClient, genericName, formatVersion, sourceURL, reason string) {
	existing, found, _ := client.GetDocument("drug_knowledge_base", genericName)
	var attempts int64 = 1
	if found {
		if a, ok := existing["fetchAttempts"].(int64); ok {
			attempts = a + 1
		}
	}

	writeErr := client.SetDocument("drug_knowledge_base", genericName, map[string]interface{}{
		"genericName":    genericName,
		"status":         "manual_needed",
		"formatVersion":  formatVersion,
		"sourceUrl":      sourceURL,
		"fetchAttempts":  attempts,
		"lastFetchError": reason,
		"updatedAt":      time.Now(),
	})
	if writeErr != nil {
		fmt.Fprintf(os.Stderr, "Firestoreへの記録にも失敗しました: %v\n", writeErr)
	}
}
