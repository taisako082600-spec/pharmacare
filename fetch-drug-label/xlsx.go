package main

import (
	"archive/zip"
	"encoding/xml"
	"fmt"
	"strconv"
)

// 最小限のxlsx(Excel)パーサー。外部ライブラリを使わず標準ライブラリのみで実装している
// (xlsxの実体はZIPアーカイブ + XML。archive/zip + encoding/xml で読み取れる)。
// 数式・書式・複数シートには対応せず、1枚目のシートの値だけを文字列テーブルとして読む。

type sharedStringsXML struct {
	XMLName xml.Name `xml:"sst"`
	SI      []struct {
		T string `xml:"t"`
	} `xml:"si"`
}

type sheetXML struct {
	XMLName   xml.Name `xml:"worksheet"`
	SheetData struct {
		Row []struct {
			C []struct {
				R string `xml:"r,attr"`
				T string `xml:"t,attr"`
				V string `xml:"v"`
			} `xml:"c"`
		} `xml:"row"`
	} `xml:"sheetData"`
}

// ReadXLSXSheet1 は xlsx ファイルの1枚目のシートを行×列の文字列テーブルとして読み込む。
func ReadXLSXSheet1(path string) ([][]string, error) {
	r, err := zip.OpenReader(path)
	if err != nil {
		return nil, fmt.Errorf("xlsxを開けません: %w", err)
	}
	defer r.Close()

	var sharedStrings []string
	var sheet *sheetXML

	for _, f := range r.File {
		switch f.Name {
		case "xl/sharedStrings.xml":
			ss, err := parseSharedStrings(f)
			if err != nil {
				return nil, err
			}
			sharedStrings = ss
		case "xl/worksheets/sheet1.xml":
			s, err := parseSheet(f)
			if err != nil {
				return nil, err
			}
			sheet = s
		}
	}

	if sheet == nil {
		return nil, fmt.Errorf("xl/worksheets/sheet1.xml が見つかりません")
	}

	var rows [][]string
	for _, row := range sheet.SheetData.Row {
		maxCol := -1
		cellValues := map[int]string{}
		for _, c := range row.C {
			col, _ := colRowFromRef(c.R)
			if col > maxCol {
				maxCol = col
			}
			val := c.V
			if c.T == "s" {
				idx, err := strconv.Atoi(c.V)
				if err == nil && idx >= 0 && idx < len(sharedStrings) {
					val = sharedStrings[idx]
				}
			}
			cellValues[col] = val
		}
		rowValues := make([]string, maxCol+1)
		for col, val := range cellValues {
			rowValues[col] = val
		}
		rows = append(rows, rowValues)
	}

	return rows, nil
}

func parseSharedStrings(f *zip.File) ([]string, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	var ss sharedStringsXML
	if err := xml.NewDecoder(rc).Decode(&ss); err != nil {
		return nil, fmt.Errorf("sharedStrings.xml解析失敗: %w", err)
	}

	out := make([]string, len(ss.SI))
	for i, si := range ss.SI {
		out[i] = si.T
	}
	return out, nil
}

func parseSheet(f *zip.File) (*sheetXML, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	var sheet sheetXML
	if err := xml.NewDecoder(rc).Decode(&sheet); err != nil {
		return nil, fmt.Errorf("sheet1.xml解析失敗: %w", err)
	}
	return &sheet, nil
}

// colRowFromRef は "H16" のようなセル参照から列インデックス(0始まり)と行番号を取り出す。
func colRowFromRef(ref string) (col int, row int) {
	i := 0
	for i < len(ref) && ref[i] >= 'A' && ref[i] <= 'Z' {
		i++
	}
	colStr := ref[:i]
	rowStr := ref[i:]

	col = 0
	for _, ch := range colStr {
		col = col*26 + int(ch-'A'+1)
	}
	col--

	row, _ = strconv.Atoi(rowStr)
	return col, row
}
