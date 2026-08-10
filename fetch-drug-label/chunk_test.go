package main

import (
	"strings"
	"testing"
)

// 2019年新様式添付文書のテキスト抽出結果を模した合成サンプル。
const sampleNewFormatText = `
9. 特定の背景を有する患者に関する注意
9.1 合併症・既往歴等のある患者
消化性潰瘍の既往のある患者では悪化するおそれがある。
9.2 腎機能障害患者
腎機能低下患者では血中濃度が上昇するおそれがあるため、観察を十分に行うこと。
9.3 肝機能障害患者
肝機能障害のある患者では、症状が悪化するおそれがある。
9.8 高齢者
高齢者では一般に生理機能が低下しているため、慎重に投与すること。
10. 相互作用
10.2 併用注意
ワルファリンとの併用で作用が増強することがある。
11. 副作用
11.1 重大な副作用
ショック、アナフィラキシーがあらわれることがある。
`

func TestDetectFormatVersion(t *testing.T) {
	if got := DetectFormatVersion(sampleNewFormatText); got != "new" {
		t.Errorf("got %q, want new", got)
	}

	oldText := "慎重投与\n腎機能障害のある患者には慎重に投与すること。\n重要な基本的注意\n定期的に検査を行うこと。"
	if got := DetectFormatVersion(oldText); got != "old" {
		t.Errorf("got %q, want old", got)
	}
}

func TestChunkNewFormat_ExtractsKeySections(t *testing.T) {
	sections := ChunkNewFormat(sampleNewFormatText)

	renal, ok := sections["renal_impairment"]
	if !ok {
		t.Fatal("renal_impairment セクションが抽出されていない")
	}
	if renal.SectionNumber != "9.2" {
		t.Errorf("got sectionNumber %q, want 9.2", renal.SectionNumber)
	}
	if !strings.Contains(renal.Text, "血中濃度が上昇するおそれ") {
		t.Errorf("腎機能セクションの本文が正しく抽出されていない: %q", renal.Text)
	}

	hepatic, ok := sections["hepatic_impairment"]
	if !ok {
		t.Fatal("hepatic_impairment セクションが抽出されていない")
	}
	if !strings.Contains(hepatic.Text, "症状が悪化するおそれ") {
		t.Errorf("肝機能セクションの本文が正しく抽出されていない: %q", hepatic.Text)
	}

	elderly, ok := sections["elderly"]
	if !ok {
		t.Fatal("elderly セクションが抽出されていない")
	}
	if !strings.Contains(elderly.Text, "生理機能が低下") {
		t.Errorf("高齢者セクションの本文が正しく抽出されていない: %q", elderly.Text)
	}

	adverse, ok := sections["major_adverse_reactions"]
	if !ok {
		t.Fatal("major_adverse_reactions セクションが抽出されていない")
	}
	if !strings.Contains(adverse.Text, "ショック") {
		t.Errorf("重大な副作用セクションの本文が正しく抽出されていない: %q", adverse.Text)
	}
}

func TestChunkNewFormat_SectionsDoNotBleedIntoEachOther(t *testing.T) {
	sections := ChunkNewFormat(sampleNewFormatText)

	renal := sections["renal_impairment"]
	if strings.Contains(renal.Text, "肝機能障害") {
		t.Errorf("腎機能セクションに次のセクション(肝機能)の内容が混入している: %q", renal.Text)
	}
}

func TestChunkOldFormat_BestEffortExtraction(t *testing.T) {
	oldText := "慎重投与\n腎機能障害のある患者には血中濃度上昇のおそれがあるため慎重投与とする。\n重要な基本的注意\n定期的な検査を行うこと。"

	sections := ChunkOldFormat(oldText)

	// 旧様式では腎機能/肝機能/高齢者が「慎重投与」に混在するため精度は落ちる想定
	sv, ok := sections["renal_impairment_or_hepatic_impairment_or_elderly"]
	if !ok {
		t.Fatal("慎重投与セクションが抽出されていない")
	}
	if !strings.Contains(sv.Text, "血中濃度上昇") {
		t.Errorf("本文抽出が不正確: %q", sv.Text)
	}
}

func TestChunkAttachmentDocument_RoutesByFormat(t *testing.T) {
	sections, formatVersion := ChunkAttachmentDocument(sampleNewFormatText)
	if formatVersion != "new" {
		t.Errorf("got formatVersion %q, want new", formatVersion)
	}
	if len(sections) == 0 {
		t.Error("新様式サンプルからセクションが1件も抽出されなかった")
	}
}

func TestChunkNewFormat_EmptySectionsNotStored(t *testing.T) {
	// 9.2の直後に本文なしで次の見出しが来るケース(記載なし扱いになるべき)
	text := "9.2 腎機能障害患者\n9.3 肝機能障害患者\n肝機能障害のある患者では注意すること。"
	sections := ChunkNewFormat(text)

	if _, ok := sections["renal_impairment"]; ok {
		t.Error("本文が空のセクションは保存されないべき")
	}
	if _, ok := sections["hepatic_impairment"]; !ok {
		t.Error("本文があるセクションは保存されるべき")
	}
}
