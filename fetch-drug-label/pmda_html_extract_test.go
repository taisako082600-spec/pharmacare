package main

import (
	"os"
	"strings"
	"testing"
)

// TestExtractPMDASections_RealData は実際にPMDA(info.pmda.go.jp)から取得した
// ロキソニン錠60mgの添付文書HTML(sample_data/body_result.html)を使った検証。
// ファイルが存在しない場合はスキップする。
func TestExtractPMDASections_RealData(t *testing.T) {
	path := "sample_data/body_result.html"
	data, err := os.ReadFile(path)
	if err != nil {
		t.Skip("sample_data/body_result.html が存在しないためスキップ")
	}

	sections := ExtractPMDASections(string(data))

	renal, ok := sections["renal_impairment"]
	if !ok {
		t.Fatal("renal_impairment セクションが抽出されていない")
	}
	if !strings.Contains(renal.Text, "急性腎障害") {
		t.Errorf("腎機能セクションの本文が正しく抽出されていない: %q", renal.Text)
	}
	if renal.SectionNumber != "9.2" {
		t.Errorf("got sectionNumber %q, want 9.2", renal.SectionNumber)
	}

	hepatic, ok := sections["hepatic_impairment"]
	if !ok {
		t.Fatal("hepatic_impairment セクションが抽出されていない")
	}
	if !strings.Contains(hepatic.Text, "肝機能障害が報告") {
		t.Errorf("肝機能セクションの本文が正しく抽出されていない: %q", hepatic.Text)
	}

	elderly, ok := sections["elderly"]
	if !ok {
		t.Fatal("elderly セクションが抽出されていない")
	}
	if elderly.SectionNumber != "9.8" {
		t.Errorf("got sectionNumber %q, want 9.8", elderly.SectionNumber)
	}

	// セクション同士の内容が混ざっていないことを確認
	if strings.Contains(renal.Text, "肝機能障害を悪化") {
		t.Error("腎機能セクションに肝機能セクションの内容が混入している")
	}
}

func TestStripHTMLTags(t *testing.T) {
	html := `<div class="section"><h3 class="section_header">9.2 腎機能障害患者</h3><p>投与しないこと。</p></div>`
	got := stripHTMLTags(html)
	if !strings.Contains(got, "投与しないこと。") {
		t.Errorf("got %q", got)
	}
	if strings.Contains(got, "<") || strings.Contains(got, ">") {
		t.Errorf("HTMLタグが残っている: %q", got)
	}
}
