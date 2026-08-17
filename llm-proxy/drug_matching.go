package main

import (
	"regexp"
	"strings"
)

// NormalizeDrugName は手帳に自由入力された薬剤名を、マスタ照合用に正規化する。
// 全角/半角統一、空白除去、製薬会社名「」の除去、剤形・数量サフィックスの除去を行う。
// ここは完全にルールベースの文字列処理であり、LLMは一切関与しない
// (名寄せミスは検索全体の入り口であり、間違えると後続の判定が全部狂うため)。
func NormalizeDrugName(raw string) string {
	s := raw

	// 全角英数字→半角
	s = toHalfWidthAlnum(s)

	// 前後の空白・全角空白を除去
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, "　", "")
	s = strings.ReplaceAll(s, " ", "")

	// 「1号」「3号」など製品を区別する番号は、数字除去の対象から外す。
	// 輸液の号数は中身がまったく別物(1号=開始液 / 2号=脱水補給液 / 3号=維持液 /
	// 4号=術後回復液)なので、落とすと別の輸液の情報を返してしまう。
	s = protectProductNumbers(s)

	// ジェネリック医薬品の製薬会社名サフィックス「サワイ」「トーワ」等を除去
	s = manufacturerSuffixPattern.ReplaceAllString(s, "")

	// 剤形・数量サフィックス（60mg、錠、カプセル、mg等）を除去
	s = dosageFormPattern.ReplaceAllString(s, "")

	s = restoreProductNumbers(s)

	return s
}

// 号数の数字を、私用領域の文字へ一時的に退避する。
// 数字のままだと dosageFormPattern に食われてしまうため。
const protectedDigitBase = rune(0xE000)

func protectProductNumbers(s string) string {
	return preserveProductNumberPattern.ReplaceAllStringFunc(s, func(m string) string {
		var b strings.Builder
		for _, r := range m {
			if r >= '0' && r <= '9' {
				b.WriteRune(protectedDigitBase + (r - '0'))
			} else {
				b.WriteRune(r)
			}
		}
		return b.String()
	})
}

func restoreProductNumbers(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= protectedDigitBase && r <= protectedDigitBase+9 {
			b.WriteRune('0' + (r - protectedDigitBase))
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

var (
	manufacturerSuffixPattern = regexp.MustCompile(`[「『][^」』]*[」』]`)
	dosageFormPattern         = regexp.MustCompile(`[0-9０-９]+([.．][0-9０-９]+)?\s*(mg|mL|g|μg|%)?|錠|カプセル|散|顆粒|注|軟膏|クリーム|坐剤|貼付剤|OD錠`)

	// 「1号」「3号」のような 数字+号 の並び(全角数字は先に半角化済み)。
	preserveProductNumberPattern = regexp.MustCompile(`[0-9]+号`)
)

func toHalfWidthAlnum(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= '０' && r <= '９':
			b.WriteRune(r - '０' + '0')
		case r >= 'Ａ' && r <= 'Ｚ':
			b.WriteRune(r - 'Ａ' + 'A')
		case r >= 'ａ' && r <= 'ｚ':
			b.WriteRune(r - 'ａ' + 'a')
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

// GenericNameFromMasterFields は drug_master のドキュメント内容から、一般名として
// 採用してよい値を取り出す。採用できない場合は found=false を返す。
//
// 正規化後の名前が同じでも中身の異なる製品が存在するため(例: 「KN1号輸液」=開始液 と
// 「KN2号輸液」=脱水補給液、バイオシミラーの後続1/2/3 など)、取り込み時に成分名が
// 複数あると判定されたものには ambiguous が立っている。
// ここで候補のどれかを選んで返すと、別の薬の添付文書を根拠に注意喚起してしまうので、
// 「引けなかった」ものとして扱い、人が確認するキューへ回す。
func GenericNameFromMasterFields(fields map[string]interface{}) (string, bool) {
	if ambiguous, _ := fields["ambiguous"].(bool); ambiguous {
		return "", false
	}
	generic, _ := fields["genericName"].(string)
	return generic, generic != ""
}

// DrugMasterLookup は drug_master / drug_name_aliases への照会を抽象化するインターフェース。
// テストではFirestoreなしのモック実装を注入できる。
type DrugMasterLookup interface {
	// LookupAlias は正規化済み文字列が過去に解決済みかを確認する(drug_name_aliases)。
	LookupAlias(normalized string) (genericName string, found bool, err error)
	// LookupMaster は正規化済み商品名から一般名を引く(drug_master)。
	LookupMaster(normalized string) (genericName string, found bool, err error)
	// QueueUnmatched は名寄せ失敗をレビューキューに積む(unmatched_drug_names)。
	QueueUnmatched(rawInput, normalized string) error
}

// MatchResult は名寄せの結果。
type MatchResult struct {
	GenericName string
	Matched     bool
	Source      string // "alias" | "master" | "unmatched"
}

// MatchDrugName は自由入力の薬剤名を一般名に解決する。
// 優先順位: 解決済みキャッシュ(alias) → マスタ照合(master) → 失敗時はキューに積んで unmatched を返す。
// あいまいマッチはLLMに判定させない。一致しなければ機械的に「未解決」として扱い、
// 人（管理者）が確認するまで推測しない。
func MatchDrugName(lookup DrugMasterLookup, rawInput string) (MatchResult, error) {
	normalized := NormalizeDrugName(rawInput)
	if normalized == "" {
		return MatchResult{Matched: false, Source: "unmatched"}, nil
	}

	if generic, found, err := lookup.LookupAlias(normalized); err != nil {
		return MatchResult{}, err
	} else if found {
		return MatchResult{GenericName: generic, Matched: true, Source: "alias"}, nil
	}

	if generic, found, err := lookup.LookupMaster(normalized); err != nil {
		return MatchResult{}, err
	} else if found {
		return MatchResult{GenericName: generic, Matched: true, Source: "master"}, nil
	}

	if err := lookup.QueueUnmatched(rawInput, normalized); err != nil {
		return MatchResult{}, err
	}
	return MatchResult{Matched: false, Source: "unmatched"}, nil
}
