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

// PMDA(info.pmda.go.jp)の添付文書検索・取得。fetch-drug-label/pmda_fetch.go と
// 同一ロジック(管理画面からの直接取得のためllm-proxy側にも複製、2モジュール間で同期)。
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

const (
	pmdaSearchEndpoint = "https://www.info.pmda.go.jp/psearch/PackinsSearch"
	pmdaPackBaseURL    = "https://www.info.pmda.go.jp/go/pack/"
)

// searchResultLinkPattern は検索結果一覧から各ヒットの医薬品コードと販売名を抜き出す。
// 複数ヒット時、先頭を機械的に採用するのではなく検索クエリと販売名を突き合わせて
// 最も一致するものを選ぶため(2026-07-19、同一成分の別規格・別剤形の誤選択を防ぐ改善)。
var searchResultLinkPattern = regexp.MustCompile(`<A href="/go/pack/([A-Za-z0-9_]+)/\?view=frame[^"]*"[^>]*>([^<]*)</A>`)

type pmdaSearchHit struct {
	code        string
	productName string // 前後・内部の空白を除去済み
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

// pickBestHit は検索クエリ(商品名 or 一般名)に最も近い販売名のヒットを選ぶ。
// 完全一致 → 前方一致(規格違い等の末尾差分を許容) → 先頭ヒット(従来動作)の順で判定する。
// あいまいな場合でも機械的にどれかを選ぶ(LLMには判定させない、名寄せと同じ方針)。
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

// searchPMDAByName は商品名(または一般名)でPMDA添付文書検索を行い、
// 検索クエリに最も一致する医薬品コードを返す。
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

// FetchAttachmentDocument は商品名(または一般名)からPMDAの添付文書を検索・取得し、
// HTML本文をそのまま返す(チャンク化は呼び出し元でExtractPMDASections等を使う)。
func FetchAttachmentDocument(searchName string) (html string, sourceURL string, err error) {
	code, err := searchPMDAByName(searchName)
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
