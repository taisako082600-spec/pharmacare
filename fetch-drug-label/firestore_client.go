package main

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// FirestoreClient は Firestore REST API をサービスアカウント認証で叩く薄いクライアント。
// cloud.google.com/go/firestore 等の公式SDKは使わず、この llm-proxy がここまで一貫してきた
// 「標準ライブラリのみ・外部Goモジュール依存ゼロ」の方針を維持している。
type FirestoreClient struct {
	projectID   string
	baseURL     string
	httpClient  *http.Client
	saKey       *serviceAccountKey
	useGcloud   bool
	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
}

type serviceAccountKey struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
	TokenURI    string `json:"token_uri"`
}

const firestoreScope = "https://www.googleapis.com/auth/datastore"

// NewFirestoreClient は GOOGLE_APPLICATION_CREDENTIALS が指すサービスアカウントJSONを読み込む。
// 鍵が無い場合は gcloud のログイン情報にフォールバックする。
//
// これは taiさんの手元で動かすバッチツールなので、鍵ファイルを常備しなくても
// 実行できるようにしてある(以前は鍵をダウンロードフォルダに置いていたが、
// Windowsのストレージセンサーに自動削除されて動かなくなった経緯がある。
// 詳細は deploy 側の auth_helper.js のコメントを参照)。
func NewFirestoreClient() (*FirestoreClient, error) {
	keyPath := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
	if keyPath == "" {
		return newFirestoreClientFromGcloud()
	}

	raw, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("サービスアカウントキーの読み込みに失敗: %w", err)
	}

	var key serviceAccountKey
	if err := json.Unmarshal(raw, &key); err != nil {
		return nil, fmt.Errorf("サービスアカウントキーの解析に失敗: %w", err)
	}
	if key.TokenURI == "" {
		key.TokenURI = "https://oauth2.googleapis.com/token"
	}

	projectID := key.ProjectID
	if projectID == "" {
		return nil, fmt.Errorf("サービスアカウントキーに project_id がありません")
	}

	return &FirestoreClient{
		projectID:  projectID,
		baseURL:    fmt.Sprintf("https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents", projectID),
		httpClient: &http.Client{Timeout: 15 * time.Second},
		saKey:      &key,
	}, nil
}

// gcloud のインストール先候補(PATHが通っていない環境があるため直接も探す)。
var gcloudCandidates = []string{
	"gcloud",
	`C:\Users\OWNER\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd`,
	`C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd`,
	`C:\Program Files\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd`,
}

// newFirestoreClientFromGcloud は gcloud のログイン情報を使うクライアントを作る。
// トークンは gcloud に都度発行させるため、秘密鍵をディスクに置かなくてよい。
func newFirestoreClientFromGcloud() (*FirestoreClient, error) {
	if _, err := tokenFromGcloud(); err != nil {
		return nil, fmt.Errorf(
			"認証情報が見つかりません。gcloud auth login を実行するか、"+
				"GOOGLE_APPLICATION_CREDENTIALS にサービスアカウントキーのパスを設定してください: %w", err)
	}

	const projectID = "pharmacist-app-646df"
	return &FirestoreClient{
		projectID:  projectID,
		baseURL:    fmt.Sprintf("https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents", projectID),
		httpClient: &http.Client{Timeout: 15 * time.Second},
		useGcloud:  true,
	}, nil
}

func tokenFromGcloud() (string, error) {
	var lastErr error
	for _, bin := range gcloudCandidates {
		out, err := exec.Command(bin, "auth", "print-access-token").Output()
		if err != nil {
			lastErr = err
			continue
		}
		if token := strings.TrimSpace(string(out)); token != "" {
			return token, nil
		}
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("gcloud が見つかりませんでした")
	}
	return "", lastErr
}

// getAccessToken はOAuth2アクセストークンを取得・キャッシュする(sync.Mutex保護、期限切れ前に自動更新)。
// サービスアカウント鍵がある場合は JWT Bearer フロー(RFC 7523)を自前署名して実装し、
// 無い場合は gcloud にトークンを発行させる。
func (c *FirestoreClient) getAccessToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.accessToken != "" && time.Now().Before(c.tokenExpiry) {
		return c.accessToken, nil
	}

	if c.useGcloud {
		token, err := tokenFromGcloud()
		if err != nil {
			return "", err
		}
		c.accessToken = token
		// gcloud のトークンは通常1時間有効。余裕をみて55分でキャッシュを切る。
		c.tokenExpiry = time.Now().Add(55 * time.Minute)
		return c.accessToken, nil
	}

	block, _ := pem.Decode([]byte(c.saKey.PrivateKey))
	if block == nil {
		return "", fmt.Errorf("秘密鍵のPEMデコードに失敗しました")
	}
	parsedKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("秘密鍵の解析に失敗しました: %w", err)
	}
	privateKey, ok := parsedKey.(*rsa.PrivateKey)
	if !ok {
		return "", fmt.Errorf("RSA秘密鍵ではありません")
	}

	now := time.Now()
	header := map[string]string{"alg": "RS256", "typ": "JWT"}
	claims := map[string]interface{}{
		"iss":   c.saKey.ClientEmail,
		"scope": firestoreScope,
		"aud":   c.saKey.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(1 * time.Hour).Unix(),
	}

	headerJSON, _ := json.Marshal(header)
	claimsJSON, _ := json.Marshal(claims)
	signingInput := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimsJSON)

	hashed := sha256.Sum256([]byte(signingInput))
	signature, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, hashed[:])
	if err != nil {
		return "", fmt.Errorf("JWT署名に失敗しました: %w", err)
	}
	jwt := signingInput + "." + base64.RawURLEncoding.EncodeToString(signature)

	form := url.Values{}
	form.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	form.Set("assertion", jwt)

	resp, err := c.httpClient.Post(c.saKey.TokenURI, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("トークン取得リクエストに失敗しました: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("トークン取得に失敗しました (status %d): %s", resp.StatusCode, string(body))
	}

	var tokenResp struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", fmt.Errorf("トークンレスポンスの解析に失敗しました: %w", err)
	}

	c.accessToken = tokenResp.AccessToken
	c.tokenExpiry = now.Add(time.Duration(tokenResp.ExpiresIn-60) * time.Second) // 60秒の余裕を持って再取得
	return c.accessToken, nil
}

func (c *FirestoreClient) doRequest(method, path string, body []byte) ([]byte, int, error) {
	token, err := c.getAccessToken()
	if err != nil {
		return nil, 0, err
	}

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, c.baseURL+path, reqBody)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, err
	}
	return respBody, resp.StatusCode, nil
}

// GetDocument はドキュメントを取得し、Firestoreの型付きフィールド表現を素の map[string]interface{} に変換する。
// 存在しない場合は found=false を返す(エラーにはしない)。
func (c *FirestoreClient) GetDocument(collectionPath, docID string) (fields map[string]interface{}, found bool, err error) {
	path := "/" + collectionPath + "/" + url.PathEscape(docID)
	body, status, err := c.doRequest(http.MethodGet, path, nil)
	if err != nil {
		return nil, false, err
	}
	if status == http.StatusNotFound {
		return nil, false, nil
	}
	if status != http.StatusOK {
		return nil, false, fmt.Errorf("Firestore GET エラー (status %d): %s", status, string(body))
	}

	var doc firestoreDocument
	if err := json.Unmarshal(body, &doc); err != nil {
		return nil, false, fmt.Errorf("ドキュメントの解析に失敗しました: %w", err)
	}
	return decodeFields(doc.Fields), true, nil
}

// DeleteDocument はドキュメントを削除する。存在しなくてもエラーにしない。
func (c *FirestoreClient) DeleteDocument(collectionPath, docID string) error {
	path := "/" + collectionPath + "/" + url.PathEscape(docID)
	body, status, err := c.doRequest(http.MethodDelete, path, nil)
	if err != nil {
		return err
	}
	if status != http.StatusOK && status != http.StatusNotFound {
		return fmt.Errorf("Firestore DELETE エラー (status %d): %s", status, string(body))
	}
	return nil
}

// SetDocument はドキュメントを作成/上書きする(指定IDへの完全上書き = PATCHで全フィールド置換)。
func (c *FirestoreClient) SetDocument(collectionPath, docID string, fields map[string]interface{}) error {
	path := "/" + collectionPath + "/" + url.PathEscape(docID)
	payload, err := json.Marshal(firestoreDocument{Fields: encodeFields(fields)})
	if err != nil {
		return fmt.Errorf("ドキュメントのエンコードに失敗しました: %w", err)
	}

	body, status, err := c.doRequest(http.MethodPatch, path, payload)
	if err != nil {
		return err
	}
	if status != http.StatusOK {
		return fmt.Errorf("Firestore PATCH エラー (status %d): %s", status, string(body))
	}
	return nil
}

// AddDocument は自動採番IDでドキュメントを作成する(キュー投入用)。
func (c *FirestoreClient) AddDocument(collectionPath string, fields map[string]interface{}) (docID string, err error) {
	path := "/" + collectionPath
	payload, err := json.Marshal(firestoreDocument{Fields: encodeFields(fields)})
	if err != nil {
		return "", fmt.Errorf("ドキュメントのエンコードに失敗しました: %w", err)
	}

	body, status, err := c.doRequest(http.MethodPost, path, payload)
	if err != nil {
		return "", err
	}
	if status != http.StatusOK {
		return "", fmt.Errorf("Firestore POST エラー (status %d): %s", status, string(body))
	}

	var doc firestoreDocument
	if err := json.Unmarshal(body, &doc); err != nil {
		return "", fmt.Errorf("作成結果の解析に失敗しました: %w", err)
	}
	// doc.Name は "projects/.../documents/collection/docId" 形式
	parts := strings.Split(doc.Name, "/")
	return parts[len(parts)-1], nil
}

// ---- Firestore REST のフィールド型エンコード/デコード ----

type firestoreDocument struct {
	Name   string                    `json:"name,omitempty"`
	Fields map[string]firestoreValue `json:"fields"`
}

type firestoreValue struct {
	StringValue    *string              `json:"stringValue,omitempty"`
	IntegerValue   *string              `json:"integerValue,omitempty"`
	DoubleValue    *float64             `json:"doubleValue,omitempty"`
	BooleanValue   *bool                `json:"booleanValue,omitempty"`
	TimestampValue *string              `json:"timestampValue,omitempty"`
	NullValue      *interface{}         `json:"nullValue,omitempty"`
	MapValue       *firestoreMapValue   `json:"mapValue,omitempty"`
	ArrayValue     *firestoreArrayValue `json:"arrayValue,omitempty"`
}

type firestoreMapValue struct {
	Fields map[string]firestoreValue `json:"fields"`
}

type firestoreArrayValue struct {
	Values []firestoreValue `json:"values"`
}

func encodeFields(fields map[string]interface{}) map[string]firestoreValue {
	out := make(map[string]firestoreValue, len(fields))
	for k, v := range fields {
		out[k] = encodeValue(v)
	}
	return out
}

func encodeValue(v interface{}) firestoreValue {
	switch val := v.(type) {
	case string:
		return firestoreValue{StringValue: &val}
	case bool:
		return firestoreValue{BooleanValue: &val}
	case int:
		s := strconv.Itoa(val)
		return firestoreValue{IntegerValue: &s}
	case int64:
		s := strconv.FormatInt(val, 10)
		return firestoreValue{IntegerValue: &s}
	case float64:
		return firestoreValue{DoubleValue: &val}
	case time.Time:
		s := val.UTC().Format(time.RFC3339Nano)
		return firestoreValue{TimestampValue: &s}
	case map[string]interface{}:
		return firestoreValue{MapValue: &firestoreMapValue{Fields: encodeFields(val)}}
	case []string:
		values := make([]firestoreValue, len(val))
		for i, s := range val {
			values[i] = encodeValue(s)
		}
		return firestoreValue{ArrayValue: &firestoreArrayValue{Values: values}}
	case []interface{}:
		values := make([]firestoreValue, len(val))
		for i, item := range val {
			values[i] = encodeValue(item)
		}
		return firestoreValue{ArrayValue: &firestoreArrayValue{Values: values}}
	case nil:
		var n interface{}
		return firestoreValue{NullValue: &n}
	default:
		s := fmt.Sprintf("%v", val)
		return firestoreValue{StringValue: &s}
	}
}

func decodeFields(fields map[string]firestoreValue) map[string]interface{} {
	out := make(map[string]interface{}, len(fields))
	for k, v := range fields {
		out[k] = decodeValue(v)
	}
	return out
}

func decodeValue(v firestoreValue) interface{} {
	switch {
	case v.StringValue != nil:
		return *v.StringValue
	case v.IntegerValue != nil:
		n, _ := strconv.ParseInt(*v.IntegerValue, 10, 64)
		return n
	case v.DoubleValue != nil:
		return *v.DoubleValue
	case v.BooleanValue != nil:
		return *v.BooleanValue
	case v.TimestampValue != nil:
		t, _ := time.Parse(time.RFC3339Nano, *v.TimestampValue)
		return t
	case v.MapValue != nil:
		return decodeFields(v.MapValue.Fields)
	case v.ArrayValue != nil:
		values := make([]interface{}, len(v.ArrayValue.Values))
		for i, item := range v.ArrayValue.Values {
			values[i] = decodeValue(item)
		}
		return values
	default:
		return nil
	}
}
