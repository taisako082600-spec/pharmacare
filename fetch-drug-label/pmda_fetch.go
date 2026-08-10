package main

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

// 【実装済み、2026-07-18】
//
// 2026-07-18のセッションで、PMDA(info.pmda.go.jp)の添付文書検索・取得の実際の
// HTTPリクエストパターンを特定できた:
//
//  1. 検索: GET https://www.info.pmda.go.jp/psearch/PackinsSearch
//     ?dragname={商品名, URLエンコード}&effect=&item1=allsearch&keyword1=&type1=and
//     &item2=&keyword2=&type2=and&item3=&keyword3=&type3=and&count=10&start=1
//     → レスポンスHTML中に /go/pack/{コード}/ 形式のリンクが並ぶ
//
//  2. 本文取得: GET https://www.info.pmda.go.jp/go/pack/{コード}?view=body&lang=ja
//     → 添付文書本文がセマンティックHTML(HDR_PatientsWithRenalImpairment等の
//        安定したID付き)で返る。pmda_html_extract.go の ExtractPMDASections で
//        セクションを抽出する。
//
// ロキソニン錠60mgの実データで検索→取得→セクション抽出まで一気通貫で検証済み
// (xlsx_test.go, pmda_html_extract_test.go 参照)。
//
// 【2026-07-19追加】複数ヒット時の選択ロジックを改善(pickBestHit)。
// 従来は検索結果の先頭を機械的に採用していたため、同一成分の別規格・別剤形
// (例: 「ロキソニン」検索でゲル・テープ・パップ・錠が混在)を誤って選ぶ可能性があった。
// 検索クエリと販売名のテキスト一致度で選び直す(llm-proxy/pmda_fetch.go と同期)。
//
// 【残る注意点】
//   - dragname は「商品名」ベースの検索。「一般名」で検索した場合の挙動・精度は未検証
//     (drug_master には商品名も一般名も両方入っているため、一般名検索でも一定は
//     ヒットすると見込まれるが、要検証)。llm-proxyの/v1/admin/fetch-drug-labelは
//     この対策として searchName(実際に患者手帳に入力された商品名) を別途渡せるようにしている

const (
	pmdaSearchEndpoint = "https://www.info.pmda.go.jp/psearch/PackinsSearch"
	pmdaPackBaseURL    = "https://www.info.pmda.go.jp/go/pack/"
)

var searchResultLinkPattern = regexp.MustCompile(`<A href="/go/pack/([A-Za-z0-9_]+)/\?view=frame[^"]*"[^>]*>([^<]*)</A>`)

type pmdaSearchHit struct {
	code        string
	productName string
}

// parseSearchResults は検索結果HTMLから (医薬品コード, 販売名) の一覧を抜き出す。
func parseSearchResults(html string) []pmdaSearchHit {
	matches := searchResultLinkPattern.FindAllStringSubmatch(html, -1)
	hits := make([]pmdaSearchHit, 0, len(matches))
	for _, m := range matches {
		name := strings.Join(strings.Fields(m[2]), "")
		hits = append(hits, pmdaSearchHit{code: m[1], productName: name})
	}
	return hits
}

// pickBestHit は検索クエリに最も近い販売名のヒットを選ぶ。
// 完全一致 → 前方一致(規格違い等の末尾差分を許容) → 先頭ヒット(従来動作)の順で判定する。
func pickBestHit(hits []pmdaSearchHit, query string) (pmdaSearchHit, bool) {
	if len(hits) == 0 {
		return pmdaSearchHit{}, false
	}
	normalizedQuery := strings.Join(strings.Fields(query), "")

	for _, h := range hits {
		if h.productName == normalizedQuery {
			return h, true
		}
	}
	for _, h := range hits {
		if strings.HasPrefix(h.productName, normalizedQuery) || strings.HasPrefix(normalizedQuery, h.productName) {
			return h, true
		}
	}
	return hits[0], true
}

// searchPMDAByName は商品名でPMDA添付文書検索を行い、検索クエリに最も一致する医薬品コードを返す。
func searchPMDAByName(name string) (code string, err error) {
	params := url.Values{}
	params.Set("dragname", name)
	params.Set("effect", "")
	params.Set("item1", "allsearch")
	params.Set("keyword1", "")
	params.Set("type1", "and")
	params.Set("item2", "")
	params.Set("keyword2", "")
	params.Set("type2", "and")
	params.Set("item3", "")
	params.Set("keyword3", "")
	params.Set("type3", "and")
	params.Set("count", "10")
	params.Set("start", "1")

	reqURL := pmdaSearchEndpoint + "?" + params.Encode()

	body, err := httpGetBody(reqURL)
	if err != nil {
		return "", fmt.Errorf("PMDA検索リクエストに失敗しました: %w", err)
	}

	hits := parseSearchResults(body)
	best, ok := pickBestHit(hits, name)
	if !ok {
		return "", fmt.Errorf("「%s」に一致する医薬品がPMDA検索で見つかりませんでした", name)
	}
	return best.code, nil
}

// fetchPMDABodyHTML は医薬品コードから添付文書本文のHTMLを取得する。
func fetchPMDABodyHTML(code string) (string, error) {
	reqURL := fmt.Sprintf("%s%s?view=body&lang=ja", pmdaPackBaseURL, code)
	return httpGetBody(reqURL)
}

func httpGetBody(reqURL string) (string, error) {
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Get(reqURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTPステータス %d", resp.StatusCode)
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// FetchAttachmentDocument は商品名からPMDAの添付文書を検索・取得し、
// セクション抽出済みのHTML本文をそのまま返す(チャンク化は呼び出し元でExtractPMDASectionsを使う)。
// ここでは「取得できたHTML本文」を text として返し、呼び出し元がセクション抽出を行う設計。
func FetchAttachmentDocument(productName string) (text string, sourceURL string, err error) {
	code, err := searchPMDAByName(productName)
	if err != nil {
		return "", "", err
	}

	bodyHTML, err := fetchPMDABodyHTML(code)
	if err != nil {
		return "", "", err
	}

	sourceURL = fmt.Sprintf("%s%s?view=body&lang=ja", pmdaPackBaseURL, code)
	return bodyHTML, sourceURL, nil
}
