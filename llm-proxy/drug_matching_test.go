package main

import "testing"

func TestNormalizeDrugName(t *testing.T) {
	cases := []struct {
		name  string
		input string
		want  string
	}{
		{"先発品名そのまま", "ロキソニン", "ロキソニン"},
		{"先発品名+剤形+数量", "ロキソニン錠60mg", "ロキソニン"},
		{"先発品名+全角数量", "ロキソニン60", "ロキソニン"},
		{"ジェネリック+製薬会社サフィックス", "ロキソプロフェンNa錠60mg「サワイ」", "ロキソプロフェンNa"},
		{"ジェネリック別会社", "ロキソプロフェンNa錠60mg「トーワ」", "ロキソプロフェンNa"},
		{"前後の空白除去", "  ロキソニン  ", "ロキソニン"},
		{"全角スペース除去", "ロキソニン　60mg", "ロキソニン"},
		{"OD錠表記", "カロナールOD錠200mg", "カロナール"},
		{"全角小数点(実データで発見したバグ)", "オーラ注歯科用カートリッジ１．８ｍＬ", "オーラ歯科用カートリッジ"},
		{"半角小数点", "テスト錠1.5mg", "テスト"},

		// 輸液の号数は中身が別物(1号=開始液 / 2号=脱水補給液 / 3号=維持液 / 4号=術後回復液)。
		// 以前は数量として一緒に削られ、すべて同じキーに潰れて別の輸液の情報を返していた。
		{"輸液の号数は残す(1号)", "ＫＮ１号輸液", "KN1号輸液"},
		{"輸液の号数は残す(3号)", "ＫＮ３号輸液", "KN3号輸液"},
		{"号数が違えば別キーになる", "ソリタ－Ｔ３号輸液", "ソリタ－T3号輸液"},

		// 「号」が付かない製品番号(ソルデム3A/3AG等)までは正規化で救えない。
		// 数量表記と区別できず、無理に残すと通常の名寄せを壊すため、ここは潰れる前提。
		// 代わりに、成分名が食い違う衝突は import 時に ambiguous を立て、
		// LookupMaster が一般名を返さないようにして誤った情報提供を防いでいる。
		{"号が付かない製品番号は潰れる(ambiguousで担保)", "ソルデム３Ａ輸液500mL", "ソルデムA輸液"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := NormalizeDrugName(c.input)
			if got != c.want {
				t.Errorf("NormalizeDrugName(%q) = %q, want %q", c.input, got, c.want)
			}
		})
	}
}

// mockDrugLookup はテスト用のインメモリ実装。
type mockDrugLookup struct {
	aliases    map[string]string
	master     map[string]string
	queuedRaw  []string
	queuedNorm []string
}

func (m *mockDrugLookup) LookupAlias(normalized string) (string, bool, error) {
	g, ok := m.aliases[normalized]
	return g, ok, nil
}

func (m *mockDrugLookup) LookupMaster(normalized string) (string, bool, error) {
	g, ok := m.master[normalized]
	return g, ok, nil
}

func (m *mockDrugLookup) QueueUnmatched(rawInput, normalized string) error {
	m.queuedRaw = append(m.queuedRaw, rawInput)
	m.queuedNorm = append(m.queuedNorm, normalized)
	return nil
}

func TestMatchDrugName_AliasHit(t *testing.T) {
	lookup := &mockDrugLookup{
		aliases: map[string]string{"ロキソニン": "ロキソプロフェンナトリウム水和物"},
		master:  map[string]string{},
	}

	result, err := MatchDrugName(lookup, "ロキソニン60mg")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !result.Matched || result.Source != "alias" {
		t.Errorf("got %+v, want matched via alias", result)
	}
	if result.GenericName != "ロキソプロフェンナトリウム水和物" {
		t.Errorf("got genericName %q", result.GenericName)
	}
	if len(lookup.queuedRaw) != 0 {
		t.Errorf("alias一致時はキューに積まれるべきではない")
	}
}

func TestMatchDrugName_MasterHit(t *testing.T) {
	lookup := &mockDrugLookup{
		aliases: map[string]string{},
		master:  map[string]string{"ロキソニン": "ロキソプロフェンナトリウム水和物"},
	}

	result, err := MatchDrugName(lookup, "ロキソニン錠60mg")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !result.Matched || result.Source != "master" {
		t.Errorf("got %+v, want matched via master", result)
	}
}

func TestMatchDrugName_Unmatched_QueuesForReview(t *testing.T) {
	lookup := &mockDrugLookup{
		aliases: map[string]string{},
		master:  map[string]string{},
	}

	result, err := MatchDrugName(lookup, "謎の薬剤X")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Matched {
		t.Errorf("マスタにない薬剤はMatched=falseであるべき: got %+v", result)
	}
	if result.Source != "unmatched" {
		t.Errorf("got source %q, want unmatched", result.Source)
	}
	if len(lookup.queuedRaw) != 1 || lookup.queuedRaw[0] != "謎の薬剤X" {
		t.Errorf("未解決の薬剤はレビューキューに積まれるべき: got %v", lookup.queuedRaw)
	}
}

func TestMatchDrugName_DoesNotGuessOnAmbiguity(t *testing.T) {
	// あいまい一致でも、LLM的な推測はせず未解決として扱うことの確認。
	lookup := &mockDrugLookup{
		aliases: map[string]string{},
		master:  map[string]string{"ロキソニン": "ロキソプロフェンナトリウム水和物"},
	}

	// 正規化後 "ロキソニンS" は "ロキソニン" と完全一致しない(あいまい)
	result, err := MatchDrugName(lookup, "ロキソニンS錠")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Matched {
		t.Errorf("完全一致しない場合は自動確定せずキューに積むべき: got %+v", result)
	}
}

// 正規化後の名前が同じでも成分が違う製品は、一般名を推測で返してはいけない。
// (実データで36グループ存在。例: KN1号輸液=開始液 と KN2号輸液=脱水補給液)
func TestGenericNameFromMasterFields(t *testing.T) {
	cases := []struct {
		name      string
		fields    map[string]interface{}
		wantName  string
		wantFound bool
	}{
		{
			name:      "あいまいでなければ一般名を返す",
			fields:    map[string]interface{}{"genericName": "ロキソプロフェンナトリウム", "ambiguous": false},
			wantName:  "ロキソプロフェンナトリウム",
			wantFound: true,
		},
		{
			name:      "ambiguousフィールドが無い古いデータも返す",
			fields:    map[string]interface{}{"genericName": "ロキソプロフェンナトリウム"},
			wantName:  "ロキソプロフェンナトリウム",
			wantFound: true,
		},
		{
			name: "あいまいなら一般名を返さない",
			fields: map[string]interface{}{
				"genericName":           "開始液",
				"ambiguous":             true,
				"ambiguousGenericNames": []string{"開始液", "維持液", "脱水補給液"},
			},
			wantName:  "",
			wantFound: false,
		},
		{
			name:      "一般名が空なら引けない",
			fields:    map[string]interface{}{"genericName": "", "ambiguous": false},
			wantName:  "",
			wantFound: false,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, found := GenericNameFromMasterFields(c.fields)
			if got != c.wantName || found != c.wantFound {
				t.Errorf("got (%q, %v), want (%q, %v)", got, found, c.wantName, c.wantFound)
			}
		})
	}
}
