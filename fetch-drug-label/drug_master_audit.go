package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

// RunAuditDrugMaster は薬価基準収載品目リストを取り込まずに解析だけ行い、
// 正規化後の名前(＝drug_masterのドキュメントID)の衝突状況を報告する。
//
// 背景: import-master は SetDocument(docID = 正規化後の品名) で書き込むため、
// 正規化後が同じになる品目は上書きされ、最後の1件だけが残る。
// このため「取り込み件数」と「実際のドキュメント数」は一致しない
// (2026-08-17: 記録上12,413件に対し実データ6,260件だったことから発覚)。
//
// 衝突には2種類あり、意味がまったく違う:
//
//	無害な衝突 … 同じ成分の後発品が製薬会社違いで並んでいるだけ。
//	            例:「〜錠60mg「サワイ」」と「〜錠60mg「トーワ」」
//	            正規化で会社名が落ちるので同じIDになるが、成分名は同一なので実害がない。
//
//	有害な衝突 … 正規化後は同じIDなのに成分名が異なる。
//	            商品名から一般名を引く用途で誤った成分名を返してしまう。
//
// このコマンドは後者だけを抽出して報告する。書き込みは一切行わない。
func RunAuditDrugMaster() {
	type entry struct {
		brandRaw    string
		genericName string
		category    string
	}

	priceListSourceFiles, err := resolvePriceListSourceFiles()
	if err != nil {
		fmt.Fprintf(os.Stderr, "取り込み元URLの解決に失敗しました: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("取り込み元 %d ファイルを検出しました\n\n", len(priceListSourceFiles))

	// 正規化後ID -> 出現した (品名, 成分名) の一覧
	collisions := map[string][]entry{}
	totalRows := 0
	skipped := 0

	for category, url := range priceListSourceFiles {
		fmt.Printf("【%s】取得中...\n", category)
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
		if len(rows) == 0 || !validateHeader(rows[0]) {
			fmt.Fprintf(os.Stderr, "  列見出しが想定と異なるためスキップ\n")
			continue
		}

		countThisFile := 0
		for i, row := range rows {
			if i == 0 || len(row) <= colManufacturer {
				continue
			}
			genericName := strings.TrimSpace(row[colGenericName])
			brandName := strings.TrimSpace(row[colBrandName])
			if genericName == "" || brandName == "" {
				skipped++
				continue
			}
			normalized := NormalizeDrugName(brandName)
			if normalized == "" {
				skipped++
				continue
			}
			collisions[normalized] = append(collisions[normalized], entry{
				brandRaw: brandName, genericName: genericName, category: category,
			})
			countThisFile++
			totalRows++
		}
		fmt.Printf("  %d行\n", countThisFile)
	}

	// 集計
	distinct := len(collisions)
	benign := 0
	harmful := map[string][]entry{}
	for id, es := range collisions {
		if len(es) == 1 {
			continue
		}
		names := map[string]bool{}
		for _, e := range es {
			names[e.genericName] = true
		}
		if len(names) == 1 {
			benign++
		} else {
			harmful[id] = es
		}
	}

	fmt.Println()
	fmt.Println("==================== 集計 ====================")
	fmt.Printf("元データの有効行数           : %d\n", totalRows)
	fmt.Printf("正規化後のユニーク件数       : %d  ← drug_master の想定ドキュメント数\n", distinct)
	fmt.Printf("上書きで消えた行数           : %d\n", totalRows-distinct)
	fmt.Printf("  うち無害(成分名が同一)     : %d グループ\n", benign)
	fmt.Printf("  うち有害(成分名が異なる)   : %d グループ  ← 誤った一般名を返す恐れ\n", len(harmful))
	fmt.Printf("成分名/品名が空でスキップ    : %d\n", skipped)
	fmt.Println("==============================================")

	if len(harmful) == 0 {
		fmt.Println("\n成分名が食い違う衝突はありませんでした。件数差は後発品の名寄せによるもので、実害はありません。")
		return
	}

	keys := make([]string, 0, len(harmful))
	for k := range harmful {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	fmt.Printf("\n■ 成分名が食い違う衝突 (先頭50件まで表示)\n")
	for i, k := range keys {
		if i >= 50 {
			fmt.Printf("...ほか %d 件\n", len(keys)-50)
			break
		}
		fmt.Printf("\n  ID: %s\n", k)
		for _, e := range harmful[k] {
			fmt.Printf("      [%s] %s  →  %s\n", e.category, e.brandRaw, e.genericName)
		}
	}
}
