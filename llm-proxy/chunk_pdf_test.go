package main

import "testing"

// PDFから抜き出したテキストは、HTMLと違ってタグが無く、章見出しが独立行として
// 現れる。管理画面の手動登録(adminParseLabelTextHandler)はこの形のテキストを
// ChunkAttachmentDocument へ渡すので、その前提が実際に成り立つかを固定する。
//
// 見出しが独立行にならない(＝pdf.js側で hasEOL を無視して連結してしまう)と
// 章が1件も取れなくなる。それを検知するための負のケースも置く。

// pdf.js が hasEOL を改行に戻したときに得られる形。新様式の添付文書を模す。
const pdfExtractedNewFormat = `カルボシステイン錠500mg「トーワ」
2. 禁忌
本剤の成分に対し過敏症の既往歴のある患者
8. 重要な基本的注意
まれにショック、アナフィラキシーを起こすことがあるので、
観察を十分に行い、異常が認められた場合には投与を中止すること。
9. 特定の背景を有する患者に関する注意
9.2 腎機能障害患者
排泄が遅延し、血中濃度が上昇するおそれがある。
9.3 肝機能障害患者
肝機能障害を悪化させるおそれがある。
9.8 高齢者
一般に生理機能が低下しているので減量するなど注意すること。
11. 副作用
11.1 重大な副作用
ショック、アナフィラキシー(頻度不明)
皮膚粘膜眼症候群(Stevens-Johnson症候群)
11.2 その他の副作用
発疹、そう痒感
`

func TestChunkAttachmentDocumentOnPDFExtractedText(t *testing.T) {
	sections, formatVersion := ChunkAttachmentDocument(pdfExtractedNewFormat)

	if formatVersion != "new" {
		t.Fatalf("新様式として判定されるべき: formatVersion=%q", formatVersion)
	}

	wantContains := map[string]string{
		"renal_impairment":        "排泄が遅延",
		"hepatic_impairment":      "肝機能障害を悪化",
		"elderly":                 "生理機能が低下",
		"important_precautions":   "アナフィラキシー",
		"major_adverse_reactions": "Stevens-Johnson",
	}

	for category, needle := range wantContains {
		section, ok := sections[category]
		if !ok {
			t.Errorf("%s が抽出されていない", category)
			continue
		}
		if !contains(section.Text, needle) {
			t.Errorf("%s の本文に %q が含まれていない: %q", category, needle, section.Text)
		}
	}

	// 9.2 の本文が 9.3 の本文まで飲み込んでいないこと。
	// 飲み込むと、腎機能の注意点として肝機能の記載が表示されてしまう。
	if renal, ok := sections["renal_impairment"]; ok {
		if contains(renal.Text, "肝機能障害を悪化") {
			t.Errorf("9.2 の本文が次章まで含んでいる: %q", renal.Text)
		}
	}
}

// 改行が失われた場合(pdf.jsのhasEOLを無視して連結した場合)は章を取り出せない。
// PDF取り込みが黙って空の結果を返すのではなく、画面が「判別できませんでした」と
// 言えるように、0件になることを明示的に確かめておく。
func TestChunkAttachmentDocumentFailsWithoutLineBreaks(t *testing.T) {
	flattened := ""
	for _, r := range pdfExtractedNewFormat {
		if r == '\n' {
			flattened += " "
			continue
		}
		flattened += string(r)
	}

	sections, _ := ChunkAttachmentDocument(flattened)
	if len(sections) != 0 {
		t.Fatalf("改行が無いテキストから章が取れてしまっている(%d件)。"+
			"pdf.js側の改行復元が効いているかを確認すること", len(sections))
	}
}

func contains(haystack, needle string) bool {
	return len(haystack) >= len(needle) && indexOf(haystack, needle) >= 0
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}
