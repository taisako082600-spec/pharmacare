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
