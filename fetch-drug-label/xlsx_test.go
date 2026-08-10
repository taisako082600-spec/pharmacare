package main

import (
	"os"
	"testing"
)

// TestReadXLSXSheet1_RealMHLWData は実際に厚労省サイトからダウンロードした
// 歯科用薬剤の薬価基準収載品目リスト(sample_data/dental.xlsx)を使った検証。
// このファイルはリポジトリには含めず、事前にダウンロードして手元に置いた状態でのみ実行される
// (CI等でファイルがない場合はスキップする)。
func TestReadXLSXSheet1_RealMHLWData(t *testing.T) {
	path := "sample_data/dental.xlsx"
	if _, err := os.Stat(path); err != nil {
		t.Skip("sample_data/dental.xlsx が存在しないためスキップ")
	}

	rows, err := ReadXLSXSheet1(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(rows) < 3 {
		t.Fatalf("got %d rows, want at least 3", len(rows))
	}

	// ヘッダー行(1行目)の列位置を確認: C列(index 2)=成分名, H列(index 7)=品名, I列(index 8)=メーカー名
	header := rows[0]
	if header[2] != "成分名" {
		t.Errorf("header col C = %q, want 成分名", header[2])
	}
	if header[7] != "品名" {
		t.Errorf("header col H = %q, want 品名", header[7])
	}
	if header[8] != "メーカー名" {
		t.Errorf("header col I = %q, want メーカー名", header[8])
	}

	// 最初のデータ行(rows[1]、1行目=rows[0]は見出しのみ)の実データを確認
	dataRow := rows[1]
	if dataRow[2] != "リドカイン塩酸塩・アドレナリン酒石酸水素塩" {
		t.Errorf("row1 成分名 = %q", dataRow[2])
	}
	if dataRow[7] != "オーラ注歯科用カートリッジ１．８ｍＬ" {
		t.Errorf("row1 品名 = %q", dataRow[7])
	}
	if dataRow[8] != "ジーシー昭和薬品" {
		t.Errorf("row1 メーカー名 = %q", dataRow[8])
	}
}

func TestColRowFromRef(t *testing.T) {
	cases := []struct {
		ref     string
		wantCol int
		wantRow int
	}{
		{"A1", 0, 1},
		{"C3", 2, 3},
		{"H16", 7, 16},
		{"I2", 8, 2},
		{"Z1", 25, 1},
		{"AA1", 26, 1},
	}
	for _, c := range cases {
		col, row := colRowFromRef(c.ref)
		if col != c.wantCol || row != c.wantRow {
			t.Errorf("colRowFromRef(%q) = (%d, %d), want (%d, %d)", c.ref, col, row, c.wantCol, c.wantRow)
		}
	}
}
