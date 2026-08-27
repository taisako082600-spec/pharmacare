package main

import (
	"os"
	"testing"
)

// PMDA検索が全角の薬剤名を引けるかを、実際のサイトに当てて確かめる調査用テスト。
// 外部ネットワークに出るので通常のテスト実行では走らせない。
//
//	go test -run TestPMDALiveProbe -v ./...   (PMDA_LIVE=1 が必要)
func TestPMDALiveProbe(t *testing.T) {
	if os.Getenv("PMDA_LIVE") == "" {
		t.Skip("PMDA_LIVE=1 のときだけ実行する(外部サイトへアクセスするため)")
	}

	cases := []string{
		"クラリスロマイシン錠２００ｍｇ「大正」", // 手帳QRから来た生の文字列(全角)
		"クラリスロマイシン錠200mg「大正」",  // 全角→半角にしたもの
		"クラリスロマイシン",                     // 一般名だけ
	}

	for _, q := range cases {
		_, sourceURL, err := FetchAttachmentDocument(q)
		if err != nil {
			t.Logf("NG  %-30q -> %v", q, err)
			continue
		}
		t.Logf("OK  %-30q -> %s", q, sourceURL)
	}
}
