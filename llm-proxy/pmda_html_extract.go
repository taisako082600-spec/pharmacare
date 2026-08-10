package main

import (
	"regexp"
	"strings"
)

// pmdaSectionIDs はPMDA添付文書HTML(info.pmda.go.jp/go/pack/{code}?view=body)における、
// セクションごとの安定したHTML ID。日本語の数字見出し(9.2等)を正規表現で探すより、
// このID(英語のセマンティックID、XMLスキーマ由来)を手がかりにする方が改版による
// 表現ゆれの影響を受けにくく堅牢。2026-07-18、ロキソニン錠60mgの実データで確認・検証済み。
// (fetch-drug-label/pmda_html_extract.go と同一ロジック、管理画面からの直接取得のためllm-proxy側にも複製)
var pmdaSectionIDs = map[string]string{
	"HDR_PatientsWithRenalImpairment":   "renal_impairment",
	"HDR_PatientsWithHepaticImpairment": "hepatic_impairment",
	"HDR_UseInTheElderly":               "elderly",
	"HDR_ImportantPrecautions":          "important_precautions",
	"HDR_SeriousAdverseEvents":          "major_adverse_reactions",
}

var (
	sectionDivStartPattern = regexp.MustCompile(`<div class="section"`)
	// トップレベルセクションの境界のみを検出する。小項目(9.2.1等)のアンカーは
	// <li id="..."> に繋がるため、<div class="section" に繋がるものだけを対象にする
	// (実データ検証で、単純な<a name="HDR_だけだと小項目アンカーを誤検出することが判明)。
	nextHDRAnchorPattern   = regexp.MustCompile(`<a name="HDR_[A-Za-z]+"></a>\s*<div class="section"`)
	sectionHeaderH3Pattern = regexp.MustCompile(`<h3 class="section_header">([^<]*)</h3>`)
	htmlTagPattern         = regexp.MustCompile(`<[^>]*>`)
	scriptStylePattern     = regexp.MustCompile(`(?s)<(script|style)[^>]*>.*?</(script|style)>`)
	whitespacePattern      = regexp.MustCompile(`[ \t]+`)
	sectionNumberPattern   = regexp.MustCompile(`^([0-9]+(?:\.[0-9]+)?)\s*`)
)

// ExtractPMDASections はPMDA添付文書のHTML本文から、既知のセクションIDに対応する
// 内容を抽出する。chunk.go の番号ベースチャンカー(ChunkNewFormat)より優先度が高い、
// より信頼できる抽出方法。
func ExtractPMDASections(html string) map[string]DrugKnowledgeSection {
	sections := make(map[string]DrugKnowledgeSection)

	for hdrID, category := range pmdaSectionIDs {
		idMarker := `id="` + hdrID + `"`
		idPos := strings.Index(html, idMarker)
		if idPos < 0 {
			continue
		}

		// idMarkerの手前にある直近の <div class="section" がこのセクションの開始位置
		sectionStart := lastIndexBefore(html, sectionDivStartPattern, idPos)
		if sectionStart < 0 {
			sectionStart = idPos
		}

		// idMarker以降で最初に現れる <a name="HDR_ が次のセクションの開始マーカー
		rest := html[idPos+len(idMarker):]
		nextLoc := nextHDRAnchorPattern.FindStringIndex(rest)

		var sectionHTML string
		if nextLoc == nil {
			sectionHTML = html[sectionStart:]
		} else {
			sectionHTML = html[sectionStart : idPos+len(idMarker)+nextLoc[0]]
		}

		title := extractSectionTitle(sectionHTML)
		bodyText := stripHTMLTags(sectionHTML)
		bodyText = strings.TrimPrefix(bodyText, title)
		bodyText = strings.TrimSpace(bodyText)

		if bodyText == "" {
			continue
		}

		sections[category] = DrugKnowledgeSection{
			SectionNumber: extractSectionNumber(title),
			SectionTitle:  title,
			Text:          bodyText,
		}
	}

	return sections
}

func lastIndexBefore(s string, pattern *regexp.Regexp, before int) int {
	matches := pattern.FindAllStringIndex(s[:before], -1)
	if len(matches) == 0 {
		return -1
	}
	return matches[len(matches)-1][0]
}

func extractSectionTitle(sectionHTML string) string {
	m := sectionHeaderH3Pattern.FindStringSubmatch(sectionHTML)
	if m == nil {
		return ""
	}
	return strings.TrimSpace(m[1])
}

func extractSectionNumber(title string) string {
	m := sectionNumberPattern.FindStringSubmatch(title)
	if m == nil {
		return ""
	}
	return strings.TrimSpace(m[1])
}

// stripHTMLTags はHTMLタグを除去してプレーンテキスト化する簡易実装。
func stripHTMLTags(html string) string {
	html = scriptStylePattern.ReplaceAllString(html, "")
	text := htmlTagPattern.ReplaceAllString(html, "\n")
	text = strings.ReplaceAll(text, "&nbsp;", " ")
	text = strings.ReplaceAll(text, "&amp;", "&")
	text = strings.ReplaceAll(text, "&lt;", "<")
	text = strings.ReplaceAll(text, "&gt;", ">")

	lines := strings.Split(text, "\n")
	var out []string
	for _, line := range lines {
		line = whitespacePattern.ReplaceAllString(strings.TrimSpace(line), " ")
		if line != "" {
			out = append(out, line)
		}
	}
	return strings.Join(out, "\n")
}
