package main

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// firebaseCertsURL はFirebase(Google)がIDトークン署名検証用の公開鍵証明書を公開しているURL。
// テストから差し替えられるよう var にしている。
var firebaseCertsURL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"

// FirebaseClaims は検証済みFirebase IDトークンから取り出したクレーム。
type FirebaseClaims struct {
	UID   string `json:"sub"`
	Email string `json:"email"`
	Iss   string `json:"iss"`
	Aud   string `json:"aud"`
	Exp   int64  `json:"exp"`
	Iat   int64  `json:"iat"`
}

type jwtHeader struct {
	Alg string `json:"alg"`
	Kid string `json:"kid"`
}

// firebaseKeySet はGoogleの公開鍵証明書をキャッシュし、有効期限が切れたら再取得する。
// 複数リクエストが同時に検証を行っても安全なよう sync.Mutex で保護する
// (go-crud-sample / token_budget.go と同じ Lock -> defer Unlock パターン)。
type firebaseKeySet struct {
	mu      sync.Mutex
	certs   map[string]*rsa.PublicKey
	expires time.Time
}

var keySet = &firebaseKeySet{}

func (k *firebaseKeySet) getKey(kid string) (*rsa.PublicKey, error) {
	k.mu.Lock()
	defer k.mu.Unlock()

	if k.certs == nil || time.Now().After(k.expires) {
		if err := k.refreshLocked(); err != nil {
			return nil, err
		}
	}

	key, ok := k.certs[kid]
	if !ok {
		return nil, fmt.Errorf("公開鍵が見つかりません (kid=%s)", kid)
	}
	return key, nil
}

func (k *firebaseKeySet) refreshLocked() error {
	resp, err := http.Get(firebaseCertsURL)
	if err != nil {
		return fmt.Errorf("Google公開鍵の取得に失敗: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("Google公開鍵レスポンスの読み取りに失敗: %w", err)
	}

	var raw map[string]string
	if err := json.Unmarshal(body, &raw); err != nil {
		return fmt.Errorf("Google公開鍵レスポンスの解析に失敗: %w", err)
	}

	certs := make(map[string]*rsa.PublicKey, len(raw))
	for kid, pemStr := range raw {
		block, _ := pem.Decode([]byte(pemStr))
		if block == nil {
			continue
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			continue
		}
		pubKey, ok := cert.PublicKey.(*rsa.PublicKey)
		if !ok {
			continue
		}
		certs[kid] = pubKey
	}

	// Cache-Control: max-age=... を尊重してキャッシュ期限を決める。取得できなければ1時間とする。
	maxAge := 1 * time.Hour
	if cc := resp.Header.Get("Cache-Control"); cc != "" {
		for _, part := range strings.Split(cc, ",") {
			part = strings.TrimSpace(part)
			if strings.HasPrefix(part, "max-age=") {
				if secs, err := time.ParseDuration(strings.TrimPrefix(part, "max-age=") + "s"); err == nil {
					maxAge = secs
				}
			}
		}
	}

	k.certs = certs
	k.expires = time.Now().Add(maxAge)
	return nil
}

func base64URLDecode(s string) ([]byte, error) {
	if m := len(s) % 4; m != 0 {
		s += strings.Repeat("=", 4-m)
	}
	return base64.URLEncoding.DecodeString(s)
}

// VerifyFirebaseIDToken はFirebase Authが発行したIDトークンを検証し、クレームを返す。
// firebase-admin-go 等の外部依存は追加せず、署名検証・有効期限・issuer/audienceの
// チェックまで標準ライブラリのみで実装している(go-crud-sample系の「stdlibのみ」方針を踏襲)。
func VerifyFirebaseIDToken(idToken, projectID string) (*FirebaseClaims, error) {
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("不正なトークン形式です")
	}

	headerJSON, err := base64URLDecode(parts[0])
	if err != nil {
		return nil, fmt.Errorf("ヘッダーのデコードに失敗: %w", err)
	}
	var header jwtHeader
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return nil, fmt.Errorf("ヘッダーの解析に失敗: %w", err)
	}
	if header.Alg != "RS256" {
		return nil, fmt.Errorf("サポートされていない署名アルゴリズムです: %s", header.Alg)
	}

	payloadJSON, err := base64URLDecode(parts[1])
	if err != nil {
		return nil, fmt.Errorf("ペイロードのデコードに失敗: %w", err)
	}
	var claims FirebaseClaims
	if err := json.Unmarshal(payloadJSON, &claims); err != nil {
		return nil, fmt.Errorf("ペイロードの解析に失敗: %w", err)
	}

	signature, err := base64URLDecode(parts[2])
	if err != nil {
		return nil, fmt.Errorf("署名のデコードに失敗: %w", err)
	}

	pubKey, err := keySet.getKey(header.Kid)
	if err != nil {
		return nil, err
	}

	hashed := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(pubKey, crypto.SHA256, hashed[:], signature); err != nil {
		return nil, fmt.Errorf("署名検証に失敗しました: %w", err)
	}

	now := time.Now().Unix()
	if claims.Exp <= now {
		return nil, fmt.Errorf("トークンの有効期限が切れています")
	}
	if claims.Iat > now+60 { // 時計のずれを60秒許容
		return nil, fmt.Errorf("トークンの発行時刻が未来です")
	}
	expectedIss := "https://securetoken.google.com/" + projectID
	if claims.Iss != expectedIss {
		return nil, fmt.Errorf("issuerが一致しません (got %s)", claims.Iss)
	}
	if claims.Aud != projectID {
		return nil, fmt.Errorf("audienceが一致しません (got %s)", claims.Aud)
	}
	if claims.UID == "" {
		return nil, fmt.Errorf("subject(uid)が空です")
	}

	return &claims, nil
}
