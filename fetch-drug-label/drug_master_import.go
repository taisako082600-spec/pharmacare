package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"
)

// 薬価基準収載品目リストの掲載ページ。ここからxlsxのURLを実行時に見つける。
//
// 以前はxlsxのURLを直接ハードコードしていたが、厚労省は薬価改定のたびに
// ファイル名の日付部分を変えて差し替えるため、URLが404になって取り込みが
// 丸ごと失敗する状態になっていた(2026-08-17に発覚。ハードコードしていた
// 令和8年7月15日版のうち内用薬・注射薬・外用薬の3ファイルが404、
// 更新頻度の低い歯科用薬剤だけが生き残っていた)。
// 同じことが改定のたびに起きるので、掲載ページのリンクを辿る方式に変更した。
const priceListIndexURL = "https://www.mhlw.go.jp/topics/2026/04/tp20260401-01.html"

// 掲載ページ内でのファイルの並び順(_01〜_04)とカテゴリの対応。
// この対応自体は薬価基準収載品目リストの構成として安定している。
var priceListCategoryBySuffix = map[string]string{
	"01": "内用薬",
	"02": "注射薬",
	"03": "外用薬",
	"04": "歯科用薬剤",
}

// 掲載ページから tpYYYYMMDD-01_NN.xlsx 形式のリンクを拾う。
var priceListLinkPattern = regexp.MustCompile(`(?i)(/topics/\d{4}/\d{2}/xls/tp\d{8}-01_(\d{2})\.xlsx)`)

// resolvePriceListSourceFiles は掲載ページを取得し、カテゴリ→URL の対応を返す。
// 同じカテゴリのリンクが複数ある場合(旧版が併記されている等)は、ファイル名の
// 日付が最も新しいものを採用する。
func resolvePriceListSourceFiles() (map[string]string, error) {
	resp, err := http.Get(priceListIndexURL)
	if err != nil {
		return nil, fmt.Errorf("掲載ページの取得に失敗: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("掲載ページのHTTPステータス %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("掲載ページの読み込みに失敗: %w", err)
	}

	// カテゴリごとに、見つかったパスのうち最も新しい日付のものを残す
	best := map[string]string{}
	for _, m := range priceListLinkPattern.FindAllStringSubmatch(string(body), -1) {
		path, suffix := m[1], m[2]
		category, ok := priceListCategoryBySuffix[suffix]
		if !ok {
			continue
		}
		// パスに含まれる日付文字列の大小比較で新しい方を選ぶ(tpYYYYMMDD 形式なので辞書順=時系列順)
		if cur, exists := best[category]; !exists || path > cur {
			best[category] = path
		}
	}

	if len(best) == 0 {
		return nil, fmt.Errorf("掲載ページからxlsxのリンクを1件も見つけられませんでした（ページ構成が変わった可能性があります: %s）", priceListIndexURL)
	}

	out := make(map[string]string, len(best))
	for category, path := range best {
		out[category] = "https://www.mhlw.go.jp" + path
	}
	return out, nil
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

	priceListSourceFiles, err := resolvePriceListSourceFiles()
	if err != nil {
		fmt.Fprintf(os.Stderr, "取り込み元URLの解決に失敗しました: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("取り込み元 %d ファイルを検出しました\n", len(priceListSourceFiles))

	// --- 1パス目: 全ファイルを読み、正規化後IDごとに候補を集める ---
	//
	// 以前は読みながらそのまま SetDocument していたため、正規化後が同じになる品目は
	// 黙って上書きされ、最後に読んだ1件だけが残っていた。成分が同じ後発品同士なら
	// 実害はないが、成分が違うのに同じIDになる組み合わせが実データに36グループあり
	// (例: KN1号輸液=開始液 と KN2号輸液=脱水補給液)、商品名から一般名を引くと
	// 別の薬の情報を返してしまう状態だった(2026-08-17に発覚)。
	// そこで、いったん全件をメモリに集めてから、あいまいなものに印を付けて書き込む。
	type candidate struct {
		brandName    string
		genericName  string
		manufacturer string
		category     string
	}
	collected := map[string][]candidate{}
	totalRows := 0

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

		read := 0
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

			collected[normalized] = append(collected[normalized], candidate{
				brandName: brandName, genericName: genericName,
				manufacturer: manufacturer, category: category,
			})
			read++
			totalRows++
		}
		fmt.Printf("  %d行読み込み\n", read)
	}

	if len(collected) == 0 {
		fmt.Fprintln(os.Stderr, "1件も読み込めませんでした。取り込みを中止します")
		os.Exit(1)
	}

	// --- 2パス目: 書き込み ---
	written := 0
	ambiguousCount := 0
	failed := 0

	for normalized, cands := range collected {
		// 成分名が1種類なら普通に確定。複数あるなら「どれか断定できない」印を付ける。
		names := map[string]bool{}
		for _, c := range cands {
			names[c.genericName] = true
		}

		fields := map[string]interface{}{
			"brandNameRaw":        cands[0].brandName,
			"brandNameNormalized": normalized,
			"genericName":         cands[0].genericName,
			"manufacturer":        cands[0].manufacturer,
			"category":            cands[0].category,
			"sourceRowCount":      len(cands),
			"updatedAt":           time.Now(),
		}

		if len(names) > 1 {
			// あいまいなものは llm-proxy 側の LookupMaster が「未解決」として扱い、
			// 推測で一般名を返さずレビューキューへ回す。
			ambiguousCount++
			candidateNames := make([]string, 0, len(names))
			for n := range names {
				candidateNames = append(candidateNames, n)
			}
			sort.Strings(candidateNames)
			fields["ambiguous"] = true
			fields["ambiguousGenericNames"] = candidateNames
		} else {
			fields["ambiguous"] = false
		}

		if err := client.SetDocument("drug_master", normalized, fields); err != nil {
			fmt.Fprintf(os.Stderr, "  保存失敗(%s): %v\n", normalized, err)
			failed++
			continue
		}
		written++
	}

	fmt.Println()
	fmt.Printf("✅ drug_master への取り込みが完了しました\n")
	fmt.Printf("   元データ行数           : %d\n", totalRows)
	fmt.Printf("   書き込んだドキュメント : %d\n", written)
	fmt.Printf("   うち、あいまい扱い     : %d  (成分名を断定できないため一般名を返さない)\n", ambiguousCount)
	if failed > 0 {
		fmt.Printf("   保存失敗               : %d\n", failed)
	}
	fmt.Println("   ※ 行数とドキュメント数の差は、後発品が正規化で同じ名前にまとまるためで正常です")
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

func NormalizeDrugName(raw string) string {
	s := raw

	// 全角英数字→半角
	s = toHalfWidthAlnum(s)

	// 前後の空白・全角空白を除去
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, "　", "")
	s = strings.ReplaceAll(s, " ", "")

	// 「1号」「3号」など製品を区別する番号は、数字除去の対象から外す。
	// 輸液の号数は中身がまったく別物(1号=開始液 / 2号=脱水補給液 / 3号=維持液 /
	// 4号=術後回復液)なので、落とすと別の輸液の情報を返してしまう。
	s = protectProductNumbers(s)

	// ジェネリック医薬品の製薬会社名サフィックス「サワイ」「トーワ」等を除去
	s = manufacturerSuffixPattern.ReplaceAllString(s, "")

	// 剤形・数量サフィックス（60mg、錠、カプセル、mg等）を除去
	s = dosageFormPattern.ReplaceAllString(s, "")

	s = restoreProductNumbers(s)

	return s
}

// 号数の数字を、私用領域の文字へ一時的に退避する。
// 数字のままだと dosageFormPattern に食われてしまうため。
const protectedDigitBase = rune(0xE000)

func protectProductNumbers(s string) string {
	return preserveProductNumberPattern.ReplaceAllStringFunc(s, func(m string) string {
		var b strings.Builder
		for _, r := range m {
			if r >= '0' && r <= '9' {
				b.WriteRune(protectedDigitBase + (r - '0'))
			} else {
				b.WriteRune(r)
			}
		}
		return b.String()
	})
}

func restoreProductNumbers(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= protectedDigitBase && r <= protectedDigitBase+9 {
			b.WriteRune('0' + (r - protectedDigitBase))
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

var (
	manufacturerSuffixPattern = regexp.MustCompile(`[「『][^」』]*[」』]`)
	dosageFormPattern         = regexp.MustCompile(`[0-9０-９]+([.．][0-9０-９]+)?\s*(mg|mL|g|μg|%)?|錠|カプセル|散|顆粒|注|軟膏|クリーム|坐剤|貼付剤|OD錠`)

	// 「1号」「3号」のような 数字+号 の並び(全角数字は先に半角化済み)。
	preserveProductNumberPattern = regexp.MustCompile(`[0-9]+号`)
)

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
