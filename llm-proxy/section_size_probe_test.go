package main

import (
	"os"
	"sort"
	"testing"
	"unicode/utf8"
)

// 抽出される各セクションの分量を実データで測る調査用テスト。
// 11.2「その他の副作用」は頻度別の表になっていることが多く、
// テキスト化するとどれくらいの量になるのかを見るために使う。
//
//	SECTION_PROBE_HTML=<保存したPMDAのHTML> go test -run TestSectionSizeProbe -v ./...
func TestSectionSizeProbe(t *testing.T) {
	path := os.Getenv("SECTION_PROBE_HTML")
	if path == "" {
		t.Skip("SECTION_PROBE_HTML にPMDAのHTMLファイルを指定したときだけ実行する")
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("読み込み失敗: %v", err)
	}

	sections := ExtractPMDASections(string(raw))
	if len(sections) == 0 {
		t.Fatal("セクションが1件も抽出できなかった")
	}

	type row struct {
		category string
		chars    int
	}
	var rows []row
	total := 0
	for category, section := range sections {
		n := utf8.RuneCountInString(section.Text)
		rows = append(rows, row{category, n})
		total += n
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].chars > rows[j].chars })

	for _, r := range rows {
		t.Logf("%-26s %5d 文字", r.category, r.chars)
	}
	t.Logf("%-26s %5d 文字", "合計", total)

	if s, ok := sections["other_adverse_reactions"]; ok {
		preview := []rune(s.Text)
		if len(preview) > 220 {
			preview = preview[:220]
		}
		t.Logf("11.2 冒頭220文字:\n%s", string(preview))
	} else {
		t.Log("11.2 その他の副作用は抽出されなかった")
	}
}
