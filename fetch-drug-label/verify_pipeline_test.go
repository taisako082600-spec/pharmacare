package main

import (
	"os"
	"testing"
)

// TestImportPipeline_LiveFirestoreWrite は、実際のFirestoreに対して
// 歯科用薬剤サンプル(28件)の一部を書き込み、パイプライン全体
// (xlsx解析→正規化→Firestore書き込み)が本当に動くことを検証する。
// GOOGLE_APPLICATION_CREDENTIALS が未設定の場合はスキップする(通常のCI/開発では実行されない)。
func TestImportPipeline_LiveFirestoreWrite(t *testing.T) {
	if os.Getenv("GOOGLE_APPLICATION_CREDENTIALS") == "" {
		t.Skip("GOOGLE_APPLICATION_CREDENTIALS 未設定のためスキップ")
	}
	path := "sample_data/dental.xlsx"
	if _, err := os.Stat(path); err != nil {
		t.Skip("sample_data/dental.xlsx が存在しないためスキップ")
	}

	client, err := NewFirestoreClient()
	if err != nil {
		t.Fatalf("Firestore初期化失敗: %v", err)
	}
	if client == nil {
		t.Skip("Firestoreクライアントがnil")
	}

	rows, err := ReadXLSXSheet1(path)
	if err != nil {
		t.Fatalf("xlsx解析失敗: %v", err)
	}
	if !validateHeader(rows[0]) {
		t.Fatal("ヘッダー検証に失敗")
	}

	// 最初の1件だけ実際にFirestoreへ書き込んで検証する(全件は本番運用時にtaiさんが実行)
	row := rows[1]
	genericName := row[colGenericName]
	brandName := row[colBrandName]
	manufacturer := row[colManufacturer]
	normalized := NormalizeDrugName(brandName)

	t.Logf("書き込み対象: 商品名=%q 正規化後=%q 一般名=%q メーカー=%q", brandName, normalized, genericName, manufacturer)

	err = client.SetDocument("drug_master", "_test_"+normalized, map[string]interface{}{
		"brandNameRaw":        brandName,
		"brandNameNormalized": normalized,
		"genericName":         genericName,
		"manufacturer":        manufacturer,
		"category":            "歯科用薬剤",
		"isTestData":          true,
	})
	if err != nil {
		t.Fatalf("Firestore書き込み失敗: %v", err)
	}

	// 読み戻して検証
	fields, found, err := client.GetDocument("drug_master", "_test_"+normalized)
	if err != nil {
		t.Fatalf("Firestore読み込み失敗: %v", err)
	}
	if !found {
		t.Fatal("書き込んだドキュメントが見つからない")
	}
	if fields["genericName"] != genericName {
		t.Errorf("got genericName %v, want %v", fields["genericName"], genericName)
	}

	t.Log("✅ 実Firestoreへの書き込み・読み込み検証に成功")

	// テストデータを削除(本番のdrug_masterを汚さないようクリーンアップ)
	if err := client.DeleteDocument("drug_master", "_test_"+normalized); err != nil {
		t.Logf("警告: テストデータの削除に失敗しました: %v", err)
	}
}
