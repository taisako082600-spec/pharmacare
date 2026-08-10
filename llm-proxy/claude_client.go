package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const (
	anthropicMessagesEndpoint    = "https://api.anthropic.com/v1/messages"
	anthropicCountTokensEndpoint = "https://api.anthropic.com/v1/messages/count_tokens"
	anthropicVersion             = "2023-06-01"
	defaultModel                 = "claude-haiku-4-5-20251001"

	// Claude Haiku 4.5 の公式料金(2026-07-16 Anthropic価格表で確認済み、1トークンあたりUSD/MTok)。
	// モデルを変更する場合は必ず最新の価格表で確認し直すこと(モデルごとに料金が異なる)。
	costPerMillionInputTokensUSD  = 1.00 // base input
	costPerMillionOutputTokensUSD = 5.00 // output
	cacheWriteMultiplier5Min      = 1.25 // cache_control: ephemeral (デフォルト5分TTL) の書き込み倍率
	cacheReadMultiplier           = 0.10 // キャッシュヒット時の読み取り倍率

	// Claude Haiku 4.5 でプロンプトキャッシュが有効になる最低プロンプト長(トークン数)。
	// これ未満のシステムプロンプトに cache_control を付けても実際にはキャッシュされない。
	// 現状の medicationSystemPrompt / triageSystemPrompt は数十〜百トークン程度でこの閾値を
	// 大きく下回っているため、現時点ではキャッシュは実質的に発動しない。
	// OTCトリアージの症状別ナレッジ(書籍から構造化予定)をシステムプロンプトに組み込み、
	// 4096トークンを超える規模になった時点で初めて効果が出る設計である。
	minCacheableTokensHaiku45 = 4096
)

// ClaudeClient は Anthropic Messages API を呼び出す薄いラッパー。
// システムプロンプトには cache_control: ephemeral を付与し、服薬指導・OTCトリアージ
// 両方で共通する固定ルール部分(system prompt)の再計算コストを削減する
// (Anthropicネイティブのプロンプトキャッシュ機能。自前のキャッシュ層は持たない)。
// 注記: プロンプトキャッシュは現在GA(一般提供)であり anthropic-beta ヘッダーは不要
// (2026-07-16 Anthropic公式ドキュメントで確認済み)。
type ClaudeClient struct {
	apiKey     string
	model      string
	httpClient *http.Client
}

// NewClaudeClient は環境変数からAPIキーを読み込む。
// APIキー未設定でもエラーにはせず(現状ai_drug_service.dart側もトークン見積もり待ちで未契約のため)、
// 実際にAPIを呼び出すタイミングでエラーを返す。
func NewClaudeClient() *ClaudeClient {
	model := os.Getenv("ANTHROPIC_MODEL")
	if model == "" {
		model = defaultModel
	}
	return &ClaudeClient{
		apiKey:     os.Getenv("ANTHROPIC_API_KEY"),
		model:      model,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

type systemBlock struct {
	Type         string        `json:"type"`
	Text         string        `json:"text"`
	CacheControl *cacheControl `json:"cache_control,omitempty"`
}

type cacheControl struct {
	Type string `json:"type"`
}

type messageParam struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type messagesRequest struct {
	Model     string         `json:"model"`
	MaxTokens int            `json:"max_tokens"`
	System    []systemBlock  `json:"system"`
	Messages  []messageParam `json:"messages"`
}

type messagesUsage struct {
	InputTokens              int `json:"input_tokens"`
	OutputTokens             int `json:"output_tokens"`
	CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
	CacheReadInputTokens     int `json:"cache_read_input_tokens"`
}

type contentBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type messagesResponse struct {
	Content []contentBlock `json:"content"`
	Usage   messagesUsage  `json:"usage"`
}

type countTokensRequest struct {
	Model    string         `json:"model"`
	System   []systemBlock  `json:"system"`
	Messages []messageParam `json:"messages"`
}

type countTokensResponse struct {
	InputTokens int `json:"input_tokens"`
}

// CountTokens は実際にメッセージを生成せず、送信予定の内容のトークン数だけを見積もる。
// 課金対象外のためリクエスト前の事前チェックに使える
// (ai_drug_service.dart が未接続だった理由=トークン消費量の見積もり未完了、を解決する部分)。
func (c *ClaudeClient) CountTokens(systemPrompt, userPrompt string) (int, error) {
	if c.apiKey == "" {
		return 0, fmt.Errorf("ANTHROPIC_API_KEY が設定されていません")
	}

	reqBody := countTokensRequest{
		Model:  c.model,
		System: []systemBlock{{Type: "text", Text: systemPrompt}},
		Messages: []messageParam{
			{Role: "user", Content: userPrompt},
		},
	}

	respBody, err := c.post(anthropicCountTokensEndpoint, reqBody)
	if err != nil {
		return 0, err
	}

	var result countTokensResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return 0, fmt.Errorf("count_tokens レスポンス解析失敗: %w", err)
	}
	return result.InputTokens, nil
}

// SendMessage はキャッシュ対象のシステムプロンプトとユーザープロンプトを送信し、
// 生成テキストと実際のトークン使用量(usage)を返す。
func (c *ClaudeClient) SendMessage(systemPrompt, userPrompt string, maxTokens int) (string, messagesUsage, error) {
	if c.apiKey == "" {
		return "", messagesUsage{}, fmt.Errorf("ANTHROPIC_API_KEY が設定されていません")
	}

	reqBody := messagesRequest{
		Model:     c.model,
		MaxTokens: maxTokens,
		System: []systemBlock{
			{
				Type:         "text",
				Text:         systemPrompt,
				CacheControl: &cacheControl{Type: "ephemeral"},
			},
		},
		Messages: []messageParam{
			{Role: "user", Content: userPrompt},
		},
	}

	respBody, err := c.post(anthropicMessagesEndpoint, reqBody)
	if err != nil {
		return "", messagesUsage{}, err
	}

	var result messagesResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", messagesUsage{}, fmt.Errorf("messages レスポンス解析失敗: %w", err)
	}
	if len(result.Content) == 0 {
		return "", result.Usage, fmt.Errorf("空のレスポンスを受信しました")
	}

	return result.Content[0].Text, result.Usage, nil
}

func (c *ClaudeClient) post(url string, body interface{}) ([]byte, error) {
	jsonBody, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("リクエストのJSON変換に失敗: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("リクエスト作成に失敗: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", anthropicVersion)
	// 注記: プロンプトキャッシュ/トークンカウントがベータ扱いのAPIバージョンでは
	// "anthropic-beta" ヘッダーが必要になる場合がある。最新のAnthropic公式ドキュメントを
	// 確認し、必要であれば例えば以下を追加すること:
	// req.Header.Set("anthropic-beta", "prompt-caching-2024-07-31")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Claude APIへのリクエストに失敗: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("レスポンス読み取りに失敗: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Claude API エラー (status %d): %s", resp.StatusCode, string(respBody))
	}

	return respBody, nil
}

// estimateCostUSD は usage.input_tokens(非キャッシュ分の入力)・
// cache_creation_input_tokens(キャッシュ書き込み)・cache_read_input_tokens(キャッシュ読み取り)・
// output_tokens をそれぞれの倍率で計算した概算コスト。
// 料金定数は claude-haiku-4-5 のもの。モデルを変更したら定数も更新すること。
func estimateCostUSD(usage messagesUsage) float64 {
	baseInputCost := float64(usage.InputTokens) / 1_000_000 * costPerMillionInputTokensUSD
	cacheWriteCost := float64(usage.CacheCreationInputTokens) / 1_000_000 * costPerMillionInputTokensUSD * cacheWriteMultiplier5Min
	cacheReadCost := float64(usage.CacheReadInputTokens) / 1_000_000 * costPerMillionInputTokensUSD * cacheReadMultiplier
	outputCost := float64(usage.OutputTokens) / 1_000_000 * costPerMillionOutputTokensUSD

	return baseInputCost + cacheWriteCost + cacheReadCost + outputCost
}
