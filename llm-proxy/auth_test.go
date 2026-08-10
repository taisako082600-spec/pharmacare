package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

const testProjectID = "test-project"
const testKid = "test-kid"

// generateTestCertServer は本物のGoogle証明書エンドポイントの代わりに、
// テスト用に自己署名証明書を1つ配信する httptest サーバーを立てる。
// firebaseCertsURL を差し替えて VerifyFirebaseIDToken から参照させる。
func generateTestCertServer(t *testing.T) (*httptest.Server, *rsa.PrivateKey) {
	t.Helper()

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("鍵生成に失敗: %v", err)
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "test"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}
	certDER, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		t.Fatalf("証明書作成に失敗: %v", err)
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{testKid: string(certPEM)})
	}))

	return server, priv
}

func base64URLEncodeNoPad(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}

// buildTestToken は指定したクレームでRS256署名済みの擬似Firebase IDトークンを組み立てる。
func buildTestToken(t *testing.T, priv *rsa.PrivateKey, claims FirebaseClaims) string {
	t.Helper()

	header := jwtHeader{Alg: "RS256", Kid: testKid}
	headerJSON, _ := json.Marshal(header)
	claimsJSON, _ := json.Marshal(claims)

	signingInput := base64URLEncodeNoPad(headerJSON) + "." + base64URLEncodeNoPad(claimsJSON)
	hashed := sha256.Sum256([]byte(signingInput))

	sig, err := rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, hashed[:])
	if err != nil {
		t.Fatalf("署名に失敗: %v", err)
	}

	return signingInput + "." + base64URLEncodeNoPad(sig)
}

func withTestCertsServer(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	server, priv := generateTestCertServer(t)
	t.Cleanup(server.Close)

	original := firebaseCertsURL
	firebaseCertsURL = server.URL
	t.Cleanup(func() { firebaseCertsURL = original })

	// テストごとにキーキャッシュをリセットする(前のテストのキャッシュが残らないように)。
	keySet = &firebaseKeySet{}

	return priv
}

func validClaims() FirebaseClaims {
	now := time.Now().Unix()
	return FirebaseClaims{
		UID: "user-123",
		Iss: "https://securetoken.google.com/" + testProjectID,
		Aud: testProjectID,
		Exp: now + 3600,
		Iat: now - 10,
	}
}

func TestVerifyFirebaseIDToken_Success(t *testing.T) {
	priv := withTestCertsServer(t)
	token := buildTestToken(t, priv, validClaims())

	claims, err := VerifyFirebaseIDToken(token, testProjectID)
	if err != nil {
		t.Fatalf("検証に失敗するべきではない: %v", err)
	}
	if claims.UID != "user-123" {
		t.Errorf("got uid %q, want %q", claims.UID, "user-123")
	}
}

func TestVerifyFirebaseIDToken_Expired(t *testing.T) {
	priv := withTestCertsServer(t)
	claims := validClaims()
	claims.Exp = time.Now().Add(-time.Hour).Unix()
	token := buildTestToken(t, priv, claims)

	if _, err := VerifyFirebaseIDToken(token, testProjectID); err == nil {
		t.Fatal("期限切れトークンはエラーになるべき")
	}
}

func TestVerifyFirebaseIDToken_WrongAudience(t *testing.T) {
	priv := withTestCertsServer(t)
	claims := validClaims()
	claims.Aud = "other-project"
	token := buildTestToken(t, priv, claims)

	if _, err := VerifyFirebaseIDToken(token, testProjectID); err == nil {
		t.Fatal("audienceが一致しない場合はエラーになるべき")
	}
}

func TestVerifyFirebaseIDToken_WrongIssuer(t *testing.T) {
	priv := withTestCertsServer(t)
	claims := validClaims()
	claims.Iss = "https://evil.example.com/" + testProjectID
	token := buildTestToken(t, priv, claims)

	if _, err := VerifyFirebaseIDToken(token, testProjectID); err == nil {
		t.Fatal("issuerが一致しない場合はエラーになるべき")
	}
}

func TestVerifyFirebaseIDToken_TamperedSignature(t *testing.T) {
	priv := withTestCertsServer(t)
	token := buildTestToken(t, priv, validClaims())

	tampered := token[:len(token)-4] + "abcd"
	if _, err := VerifyFirebaseIDToken(tampered, testProjectID); err == nil {
		t.Fatal("署名が改ざんされている場合はエラーになるべき")
	}
}

func TestVerifyFirebaseIDToken_MalformedToken(t *testing.T) {
	withTestCertsServer(t)

	if _, err := VerifyFirebaseIDToken("not-a-valid-jwt", testProjectID); err == nil {
		t.Fatal("不正な形式のトークンはエラーになるべき")
	}
}

func TestVerifyFirebaseIDToken_UnknownKid(t *testing.T) {
	priv := withTestCertsServer(t)
	claims := validClaims()
	token := buildTestToken(t, priv, claims)

	// kid を存在しない値に差し替える
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{})
	}))
	defer server.Close()
	firebaseCertsURL = server.URL
	keySet = &firebaseKeySet{}

	if _, err := VerifyFirebaseIDToken(token, testProjectID); err == nil {
		t.Fatal("未知のkidの場合はエラーになるべき")
	} else {
		fmt.Println("expected error:", err)
	}
}
