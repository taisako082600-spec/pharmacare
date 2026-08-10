package main

import "testing"

func f64(v float64) *float64 { return &v }
func iptr(v int) *int        { return &v }

func TestShouldSurfaceSection_RenalImpairment(t *testing.T) {
	cases := []struct {
		name string
		text string
		egfr *float64
		want bool
	}{
		{"セクション記載あり・eGFR正常 → 非表示", "腎機能低下患者は注意", f64(75), false},
		{"セクション記載あり・eGFR要注意 → 表示", "腎機能低下患者は注意", f64(45), true},
		{"セクション記載あり・eGFR低下 → 表示", "腎機能低下患者は注意", f64(20), true},
		{"セクション記載あり・eGFR未記録 → 非表示", "腎機能低下患者は注意", nil, false},
		{"セクション記載なし → 常に非表示", "", f64(20), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := ShouldSurfaceSection("renal_impairment", c.text, c.egfr, "", nil)
			if got != c.want {
				t.Errorf("got %v, want %v", got, c.want)
			}
		})
	}
}

func TestShouldSurfaceSection_HepaticImpairment(t *testing.T) {
	cases := []struct {
		name        string
		text        string
		liverStatus string
		want        bool
	}{
		{"肝機能正常 → 非表示", "肝機能障害患者は注意", "正常", false},
		{"肝機能軽度異常 → 表示", "肝機能障害患者は注意", "軽度異常", true},
		{"肝機能高度異常 → 表示", "肝機能障害患者は注意", "高度", true},
		{"肝機能未記録(空文字) → 非表示", "肝機能障害患者は注意", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := ShouldSurfaceSection("hepatic_impairment", c.text, nil, c.liverStatus, nil)
			if got != c.want {
				t.Errorf("got %v, want %v", got, c.want)
			}
		})
	}
}

func TestShouldSurfaceSection_Elderly(t *testing.T) {
	cases := []struct {
		name string
		age  *int
		want bool
	}{
		{"64歳 → 非表示", iptr(64), false},
		{"65歳ちょうど → 表示", iptr(65), true},
		{"80歳 → 表示", iptr(80), true},
		{"年齢未記録 → 非表示", nil, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := ShouldSurfaceSection("elderly", "高齢者では注意", nil, "", c.age)
			if got != c.want {
				t.Errorf("got %v, want %v", got, c.want)
			}
		})
	}
}

func TestShouldSurfaceSection_OtherCategoryAlwaysShownIfPresent(t *testing.T) {
	got := ShouldSurfaceSection("major_adverse_reactions", "重大な副作用: ショック", nil, "", nil)
	if !got {
		t.Error("患者値に依存しないカテゴリは記載があれば表示されるべき")
	}

	got2 := ShouldSurfaceSection("major_adverse_reactions", "", nil, "", nil)
	if got2 {
		t.Error("記載がなければカテゴリを問わず非表示であるべき")
	}
}

func TestSelectCautionsForDrug(t *testing.T) {
	entry := DrugKnowledgeEntry{
		GenericName: "ロキソプロフェンナトリウム水和物",
		Status:      "complete",
		Sections: map[string]DrugKnowledgeSection{
			"renal_impairment": {
				SectionNumber: "9.2",
				SectionTitle:  "腎機能障害患者",
				Text:          "腎機能低下患者では血中濃度が上昇するおそれがある",
			},
			"hepatic_impairment": {
				SectionNumber: "9.3",
				SectionTitle:  "肝機能障害患者",
				Text:          "", // 記載なし
			},
		},
	}

	// eGFR低下・肝機能正常の患者 → 腎機能セクションのみ表示されるべき
	result := SelectCautionsForDrug(entry, f64(40), "正常", nil)
	if len(result) != 1 {
		t.Fatalf("got %d cautions, want 1", len(result))
	}
	if result[0].Category != "renal_impairment" {
		t.Errorf("got category %q, want renal_impairment", result[0].Category)
	}
	if result[0].Reason == "" {
		t.Error("表示理由(Reason)は必ず設定されるべき")
	}
}

func TestSelectCautionsForDrug_NoCautionsWhenPatientNormal(t *testing.T) {
	entry := DrugKnowledgeEntry{
		GenericName: "テスト薬",
		Sections: map[string]DrugKnowledgeSection{
			"renal_impairment":   {SectionNumber: "9.2", Text: "腎機能に注意"},
			"hepatic_impairment": {SectionNumber: "9.3", Text: "肝機能に注意"},
		},
	}

	result := SelectCautionsForDrug(entry, f64(80), "正常", iptr(30))
	if len(result) != 0 {
		t.Errorf("患者が全て正常なら注意点は0件のはず: got %d", len(result))
	}
}
