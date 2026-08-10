package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
)

// 薬価基準収載品目リストの実データダウンロードURL(厚労省、2026-07-18時点で確認)。
// 定期的に更新される(令和8年7月15日適用版)。URLの日付部分は改定のたびに変わるため、
// 実運用では都度最新のURLを厚労省サイトで確認して更新する必要がある。
var priceListSourceFiles = map[string]string{
	"内用薬":   "https://www.mhlw.go.jp/topics/2026/04/xls/tp20260715-01_01.xlsx",
	"注射薬":   "https://www.mhlw.go.jp/topics/2026/04/xls/tp20260715-01_02.xlsx",
	"外用薬":   "https://www.mhlw.go.jp/topics/2026/04/xls/tp20260715-01_03.xlsx",
	"歯科用薬剤": "https://www.mhlw.go.jp/topics/2026/04/xls/tp20260401-01_04.xlsx",
}

// 列インデックス(0始まり)。歯科用薬剤ファイルの実データで確認した列位置
// (2026-07-18、C列=成分名/H列=品名/I列=メーカー名)。
// 内用薬・注射薬・外用薬ファイルも同じ凡例に基づき作成されているため同一列構成と想定しているが、
// 未検証(実行時に各ファイルのヘッダー行を検証し、想定と異なれば警告を出す)。
const (
	colGenericName  = 2 // C列: 成分名
	colBrandName    = 7 // H列: 品名
	colManufacturer = 8 // I列: メーカー名
)

// RunImportDrugMaster は薬価基準収載品目リストをダウンロード・解析し、
// drug_master コレクションへ一括投入する。これは「知識ベースの逐次追加」とは別軸で、
// 商品名⇔一般名のマスタデータ自体は取得コストが低い静的な参照データなので、
// 一括で全件（約1万3千品目）取り込む設計にしている。
func RunImportDrugMaster() {
	client, err := NewFirestoreClient()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Firestore初期化エラー: %v\n", err)
		os.Exit(1)
	}
	if client == nil {
		fmt.Fprintln(os.Stderr, "GOOGLE_APPLICATION_CREDENTIALS が未設定です")
		os.Exit(1)
	}

	totalImported := 0
	for category, url := range priceListSourceFiles {
		fmt.Printf("【%s】取得中... %s\n", category, url)
		path, err := downloadTemp(url)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  ダウンロード失敗: %v\n", err)
			continue
		}

		rows, err := ReadXLSXSheet1(path)
		os.Remove(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  解析失敗: %v\n", err)
			continue
		}
		if len(rows) == 0 {
			fmt.Fprintf(os.Stderr, "  空のファイルでした\n")
			continue
		}

		if !validateHeader(rows[0]) {
			fmt.Fprintf(os.Stderr, "  警告: 想定した列見出し(成分名/品名/メーカー名)と一致しません。このファイルはスキップします\n")
			continue
		}

		imported := 0
		for i, row := range rows {
			if i == 0 {
				continue // 見出し行
			}
			if len(row) <= colManufacturer {
				continue
			}
			genericName := strings.TrimSpace(row[colGenericName])
			brandName := strings.TrimSpace(row[colBrandName])
			manufacturer := strings.TrimSpace(row[colManufacturer])
			if genericName == "" || brandName == "" {
				continue
			}

			normalized := NormalizeDrugName(brandName)
			if normalized == "" {
				continue
			}

			err := client.SetDocument("drug_master", normalized, map[string]interface{}{
				"brandNameRaw":        brandName,
				"brandNameNormalized": normalized,
				"genericName":         genericName,
				"manufacturer":        manufacturer,
				"category":            category,
				"updatedAt":           time.Now(),
			})
			if err != nil {
				fmt.Fprintf(os.Stderr, "  保存失敗(%s): %v\n", brandName, err)
				continue
			}
			imported++
		}
		fmt.Printf("  %d件取り込み完了\n", imported)
		totalImported += imported
	}

	fmt.Printf("✅ 合計 %d件を drug_master に取り込みました\n", totalImported)
}

func validateHeader(header []string) bool {
	if len(header) <= colManufacturer {
		return false
	}
	return header[colGenericName] == "成分名" &&
		header[colBrandName] == "品名" &&
		header[colManufacturer] == "メーカー名"
}

func downloadTemp(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTPステータス %d", resp.StatusCode)
	}

	f, err := os.CreateTemp("", "drug-master-*.xlsx")
	if err != nil {
		return "", err
	}
	defer f.Close()

	if _, err := io.Copy(f, resp.Body); err != nil {
		return "", err
	}
	return f.Name(), nil
}

// ---- 薬剤名正規化 (llm-proxy/drug_matching.go と同一ロジックの複製) ----
// このツールは独立モジュールのため、小さな自己完結ロジックはあえて複製している
// (共有パッケージへの分割はこのプロジェクトの規模に対してオーバーエンジニアリングと判断)。

var (
	manufacturerSuffixPattern = regexp.MustCompile(`[「『][^」』]*[」』]`)
	dosageFormPattern         = regexp.MustCompile(`[0-9０-９]+([.．][0-9０-９]+)?\s*(mg|mL|g|μg|%)?|錠|カプセル|散|顆粒|注|軟膏|クリーム|坐剤|貼付剤|OD錠`)
)

// NormalizeDrugName は商品名を drug_master のキー用に正規化する。
func NormalizeDrugName(raw string) string {
	s := toHalfWidthAlnum(raw)
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, "　", "")
	s = strings.ReplaceAll(s, " ", "")
	s = manufacturerSuffixPattern.ReplaceAllString(s, "")
	s = dosageFormPattern.ReplaceAllString(s, "")
	return s
}

func toHalfWidthAlnum(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= '０' && r <= '９':
			b.WriteRune(r - '０' + '0')
		case r >= 'Ａ' && r <= 'Ｚ':
			b.WriteRune(r - 'Ａ' + 'A')
		case r >= 'ａ' && r <= 'ｚ':
			b.WriteRune(r - 'ａ' + 'a')
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
