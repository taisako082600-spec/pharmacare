package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// プリフライトが認証より前で処理されることの確認。
// ここが崩れると、ブラウザからは「プロキシに接続できません」としか見えず、
// 原因の特定が難しい不具合になる(実際に本番で発生した)。
func TestWithCORS_PreflightBypassesAuth(t *testing.T) {
	// 認証つきハンドラを包む。プリフライトなら認証に到達しないはず。
	reachedHandler := false
	h := withCORS(requireAuth("dummy-project", func(w http.ResponseWriter, r *http.Request) {
		reachedHandler = true
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodOptions, "/v1/triage", nil)
	req.Header.Set("Origin", "https://pharmacist-app-646df.web.app")
	req.Header.Set("Access-Control-Request-Method", "POST")
	rec := httptest.NewRecorder()

	h(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Errorf("プリフライトは204であるべき: got %d", rec.Code)
	}
	if reachedHandler {
		t.Error("プリフライトが本体ハンドラまで到達している")
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://pharmacist-app-646df.web.app" {
		t.Errorf("Allow-Origin が返っていない: %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); got == "" {
		t.Error("Allow-Headers が返っていない(Authorization を送れない)")
	}
}

func TestWithCORS_AllowedOrigins(t *testing.T) {
	cases := []struct {
		origin string
		want   bool
	}{
		{"https://pharmacist-app-646df.web.app", true},
		{"https://pharmacist-app-646df.firebaseapp.com", true},
		{"http://localhost:5000", true},
		{"http://127.0.0.1:8080", true},
		{"https://evil.example.com", false},
		{"", false},
		// 部分一致で通ってしまわないこと
		{"https://pharmacist-app-646df.web.app.evil.com", false},
	}
	for _, c := range cases {
		if got := isAllowedOrigin(c.origin); got != c.want {
			t.Errorf("isAllowedOrigin(%q) = %v, want %v", c.origin, got, c.want)
		}
	}
}

// 許可していないオリジンにはCORSヘッダーを返さない。
func TestWithCORS_DisallowedOriginGetsNoHeaders(t *testing.T) {
	h := withCORS(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })

	req := httptest.NewRequest(http.MethodOptions, "/v1/triage", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	rec := httptest.NewRecorder()
	h(rec, req)

	if rec.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Error("許可していないオリジンにAllow-Originを返している")
	}
	if rec.Code != http.StatusForbidden {
		t.Errorf("許可外オリジンのプリフライトは403であるべき: got %d", rec.Code)
	}
}

// 通常のリクエストにもAllow-Originが付くこと(付かないとレスポンスが読めない)。
func TestWithCORS_ActualRequestHasOrigin(t *testing.T) {
	h := withCORS(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })

	req := httptest.NewRequest(http.MethodPost, "/v1/triage", nil)
	req.Header.Set("Origin", "https://pharmacist-app-646df.web.app")
	rec := httptest.NewRecorder()
	h(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("本リクエストは通るべき: got %d", rec.Code)
	}
	if rec.Header().Get("Access-Control-Allow-Origin") == "" {
		t.Error("本リクエストのレスポンスにAllow-Originが無い")
	}
}
