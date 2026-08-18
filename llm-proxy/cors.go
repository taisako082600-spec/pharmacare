package main

import (
	"net/http"
	"os"
	"strings"
)

// ブラウザから直接叩かれるサービスなので、CORS(Cross-Origin Resource Sharing)への
// 対応が必要になる。
//
// 経緯: 当初これが無く、本番アプリから「プロキシに接続できません」となっていた
// (2026-08-18に実機で発覚)。ブラウザは実リクエストの前に OPTIONS の
// プリフライトを送るが、そこには Authorization ヘッダーが付かない仕様のため、
// 認証ミドルウェアが401で弾き、本リクエストが一度も飛んでいなかった。
// したがってプリフライトは必ず「認証より前」で処理する必要がある。
//
// 医療情報を扱い、かつ認証トークンを伴うリクエストなので、
// Access-Control-Allow-Origin にワイルドカード(*)は使わず、許可するオリジンを列挙する。

// 許可するオリジン。Firebase Hostingは web.app と firebaseapp.com の両方を払い出す。
var defaultAllowedOrigins = []string{
	"https://pharmacist-app-646df.web.app",
	"https://pharmacist-app-646df.firebaseapp.com",
}

// allowedOrigins は環境変数 ALLOWED_ORIGINS (カンマ区切り) があればそれを、
// 無ければ既定値を返す。ローカル開発で別オリジンから叩きたい場合に使う。
func allowedOrigins() []string {
	if v := os.Getenv("ALLOWED_ORIGINS"); v != "" {
		var out []string
		for _, o := range strings.Split(v, ",") {
			if o = strings.TrimSpace(o); o != "" {
				out = append(out, o)
			}
		}
		if len(out) > 0 {
			return out
		}
	}
	return defaultAllowedOrigins
}

func isAllowedOrigin(origin string) bool {
	if origin == "" {
		return false
	}
	for _, o := range allowedOrigins() {
		if o == origin {
			return true
		}
	}
	// ローカル開発(flutter run)のオリジンはポートが起動ごとに変わるため、
	// ホスト部分だけで判定する。
	if strings.HasPrefix(origin, "http://localhost:") || strings.HasPrefix(origin, "http://127.0.0.1:") {
		return true
	}
	return false
}

// withCORS はCORSヘッダーの付与とプリフライト応答を行うミドルウェア。
// 認証ミドルウェアより外側に置くこと(プリフライトは認証を通れないため)。
func withCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if isAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			// オリジンごとに応答が変わるため、キャッシュを混線させないよう明示する
			w.Header().Add("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Max-Age", "3600")
		}

		// プリフライトはここで完結させる。認証には回さない。
		if r.Method == http.MethodOptions {
			if !isAllowedOrigin(origin) {
				// 許可していないオリジンには CORS ヘッダーを返さない。
				// ブラウザ側がこれを見て本リクエストを中止する。
				w.WriteHeader(http.StatusForbidden)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next(w, r)
	}
}
