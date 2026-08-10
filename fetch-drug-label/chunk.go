package main

import (
	"regexp"
	"strings"
)

// DrugKnowledgeSection は添付文書から抽出された1セクション。
// llm-proxy/medication_rules.go の同名型とフィールドを揃えている(Firestore上で共有するため)。
type DrugKnowledgeSection struct {
	SectionNumber string `json:"sectionNumber"`
	SectionTitle  string `json:"sectionTitle"`
	Text          string `json:"text"`
}

// newFormatSectionCategories は、2019年新様式の添付文書における章番号と、
// 本アプリが使うカテゴリキーの対応表。9.2/9.3/9.8が個別最適化の中核だが、
// 8(重要な基本的注意)・11.1(重大な副作用)も参考情報として拾う。
var newFormatSectionCategories = map[string]string{
	"9.2":  "renal_impairment",
	"9.3":  "hepatic_impairment",
	"9.8":  "elderly",
	"8":    "important_precautions",
	"11.1": "major_adverse_reactions",
}

// 新様式の章見出しパターン: 行頭が "9.2" や "11.1" のような番号で始まり、
// 続けて見出しテキストが短く続く行。添付文書のテキスト抽出結果を想定した緩いマッチ。
var newFormatHeaderPattern = regexp.MustCompile(`(?m)^\s*(\d{1,2}(?:\.\d{1,2})?)\s*[\.\s　]*(.{0,40})\s*$`)

// oldFormatKeywordCategories は旧様式(2019年以前承認)添付文書の非標準見出しキーワード。
// Option A: ベストエフォートのキーワード抽出。新様式ほどの精度は期待できない。
var oldFormatKeywordCategories = map[string]string{
	"慎重投与":     "renal_impairment_or_hepatic_impairment_or_elderly", // 旧様式は腎機能/肝機能/高齢者が同一セクションに混在することが多い
	"重要な基本的注意": "important_precautions",
	"重大な副作用":   "major_adverse_reactions",
}

// ChunkNewFormat は2019年新様式の添付文書テキストを章番号ベースで分割する。
// 入力は既にPDF/HTML等から抽出済みのプレーンテキストを想定する
// (PDF抽出自体の実装は fetchAttachmentDocument 側の責務)。
func ChunkNewFormat(text string) map[string]DrugKnowledgeSection {
	sections := make(map[string]DrugKnowledgeSection)

	matches := newFormatHeaderPattern.FindAllStringSubmatchIndex(text, -1)
	if len(matches) == 0 {
		return sections
	}

	for i, m := range matches {
		sectionNumber := text[m[2]:m[3]]
		category, ok := newFormatSectionCategories[sectionNumber]
		if !ok {
			continue
		}
		title := strings.TrimSpace(text[m[4]:m[5]])

		// 本文はこの見出し行の終わりから、次に検出された見出し行の始まりまで
		bodyStart := m[1]
		bodyEnd := len(text)
		if i+1 < len(matches) {
			bodyEnd = matches[i+1][0]
		}
		body := strings.TrimSpace(text[bodyStart:bodyEnd])

		if body == "" {
			continue // 記載なしセクションは保存しない(ShouldSurfaceSectionが空文字を非表示扱いするのと一貫)
		}

		sections[category] = DrugKnowledgeSection{
			SectionNumber: sectionNumber,
			SectionTitle:  title,
			Text:          body,
		}
	}

	return sections
}

// ChunkOldFormat は旧様式添付文書のベストエフォート抽出(Option A)。
// 見出しキーワードの後から次の既知キーワードの前までを本文として扱う、簡易的な実装。
// 新様式より精度が落ちることを前提とし、抽出結果は "formatVersion: old" として
// 精度が低いことが分かるようにする。
func ChunkOldFormat(text string) map[string]DrugKnowledgeSection {
	sections := make(map[string]DrugKnowledgeSection)

	type found struct {
		keyword  string
		category string
		index    int
	}
	var hits []found
	for keyword, category := range oldFormatKeywordCategories {
		idx := strings.Index(text, keyword)
		if idx >= 0 {
			hits = append(hits, found{keyword: keyword, category: category, index: idx})
		}
	}
	if len(hits) == 0 {
		return sections
	}

	// 出現位置順にソート(簡易バブルソート、件数が少ないため十分)
	for i := 0; i < len(hits); i++ {
		for j := i + 1; j < len(hits); j++ {
			if hits[j].index < hits[i].index {
				hits[i], hits[j] = hits[j], hits[i]
			}
		}
	}

	for i, h := range hits {
		bodyStart := h.index + len(h.keyword)
		bodyEnd := len(text)
		if i+1 < len(hits) {
			bodyEnd = hits[i+1].index
		}
		body := strings.TrimSpace(text[bodyStart:bodyEnd])
		if body == "" {
			continue
		}
		sections[h.category] = DrugKnowledgeSection{
			SectionNumber: "",
			SectionTitle:  h.keyword,
			Text:          body,
		}
	}

	return sections
}

// DetectFormatVersion は添付文書テキストが新様式(2019年以降)か旧様式かを判定する簡易ヒューリスティック。
// 「9.2」のような新様式特有の章番号が見つかれば新様式とみなす。
func DetectFormatVersion(text string) string {
	if strings.Contains(text, "9.2") || strings.Contains(text, "特定の背景を有する患者") {
		return "new"
	}
	return "old"
}

// ChunkAttachmentDocument はテキストの様式を自動判定し、適切なチャンカーに振り分ける。
func ChunkAttachmentDocument(text string) (sections map[string]DrugKnowledgeSection, formatVersion string) {
	formatVersion = DetectFormatVersion(text)
	if formatVersion == "new" {
		return ChunkNewFormat(text), formatVersion
	}
	return ChunkOldFormat(text), formatVersion
}
