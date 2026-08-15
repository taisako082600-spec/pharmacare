# PharmaCare LLMプロキシ

Flutter (`ai_drug_service.dart`) から呼び出される、Claude API 連携用のGo製プロキシサーバー。

## 役割

1. **プロンプトキャッシュ** — システムプロンプトに `cache_control: ephemeral` を付与し、Anthropicネイティブのキャッシュ機能で再計算コストを削減。**注記(2026-07-16確認)**: プロンプトキャッシュは現在GA(一般提供)で `anthropic-beta` ヘッダーは不要。ただし claude-haiku-4-5 はキャッシュ有効化に最低4096トークン必要で、現状の短いシステムプロンプトでは実質的に発動しない（`claude_client.go` の `minCacheableTokensHaiku45` 参照）。OTCトリアージの症状ナレッジをシステムプロンプトに組み込む段階で効果が出る設計
2. **トークン消費量の見積もり・上限管理** — 施設単位(`FacilityTokenBudgets`)＋全体(`TokenBudget`)の二層で`sync.Mutex`保護。施設予算は公平性、全体予算は安全弁の役割分担
3. **並行リクエストの安全な処理** — `net/http` の標準ルーティング(各リクエストは自動でgoroutine化)+ 上記予算管理の排他制御。並行性は`facility_budget_test.go`の200goroutine同時アクセステストで検証済み
4. **OTCトリアージの安全弁ロジック** — `DetermineTriageResult`（`redflag.go`）がレッドフラッグ・重症度から判定を決定論的に計算。AIはこの判定結果に対する説明文生成のみを担当し、判定そのものを上書きしない。**AI呼び出しが失敗しても判定結果は必ず返す**
5. **Firebase認証** — `Authorization: Bearer <Firebase ID Token>` を標準ライブラリのみでRS256署名検証（`auth.go`）。外部SDK非依存

## 構成

```
llm-proxy/
├── main.go              # サーバー起動・ルーティング
├── handlers.go           # HTTPハンドラー (/v1/analyze-medication, /v1/triage, /healthz)
├── claude_client.go      # Anthropic Messages API クライアント (SendMessage, CountTokens)
├── token_budget.go       # 日次トークン上限管理 (sync.Mutex)
├── facility_budget.go    # 施設単位のトークン予算管理 (施設ごとに独立したTokenBudget)
├── facility_budget_test.go # 施設別予算の分離・並行アクセス安全性のテスト
├── redflag.go            # トリアージ安全弁ロジック (Flutter側と同一ロジック)
├── redflag_test.go       # 安全弁ロジックのユニットテスト
├── auth.go               # Firebase IDトークン検証 (JWT署名検証を標準ライブラリのみで実装)
├── auth_middleware.go    # requireAuth ミドルウェア (Authorization: Bearer 検証)
├── auth_test.go          # 認証ロジックのユニットテスト (自己署名証明書で署名検証まで検証)
└── models.go             # リクエスト/レスポンスの構造体定義
```

## セットアップ

```bash
# 環境変数
export ANTHROPIC_API_KEY="sk-ant-..."     # 未設定でも起動はできる(/healthzのみ応答、他はエラーを返す)
export ANTHROPIC_MODEL="claude-haiku-4-5-20251001"  # 省略可（デフォルト値を使用）
export DAILY_TOKEN_LIMIT="200000"         # 省略可（デフォルト20万トークン/日・全体の安全弁）
export DAILY_TOKEN_LIMIT_PER_FACILITY="50000"  # 省略可（デフォルト5万トークン/日・施設ごと）
export PORT="8081"                        # 省略可（デフォルト8081）
export FIREBASE_PROJECT_ID="pharmacist-app-646df"  # 省略時は認証なし(開発用のみ・起動時に警告)

go build -o llm-proxy.exe .
./llm-proxy.exe
```

## テスト

```bash
go test -v ./...
```

- 安全弁ロジック（`DetermineTriageResult`）はAPI呼び出しなしで検証可能
- 認証ロジック（`VerifyFirebaseIDToken`）は `httptest` + 自己署名RSA証明書で実際の署名検証まで通すテスト済み

## エンドポイント

すべて `FIREBASE_PROJECT_ID` 設定時は `Authorization: Bearer <Firebase ID Token>` 必須（`/healthz`, `/ping` を除く）。

### `GET /healthz` / `GET /ping`
稼働確認 + トークン予算の消費状況。認証不要。

**Cloud Run では末尾が `z` で終わるパスが予約URLパスとして扱われ、エッジ層で処理されるためコンテナに到達しません**（公式ドキュメント[「Cloud Run の既知の問題」](https://cloud.google.com/run/docs/issues)に `/eventlog`・`/_ah/` で始まるパスと並んで記載）。`/healthz`・`/livez`・`/readyz` など Kubernetes 慣習の命名はすべて該当します。**本番の死活監視には末尾が `z` にならない `/ping` を使ってください**（2026-07-20に実機でも確認済み）。ローカル開発では両方使えます。

### `POST /v1/analyze-medication`
`ai_drug_service.dart` の `analyzeVisitMedicines` と対応。

```json
{
  "medicineNames": ["ロキソニン", "ムコダイン"],
  "egfr": 45.0,
  "liverStatus": "軽度異常",
  "mainSymptom": "頭痛",
  "department": "内科"
}
```

### `POST /v1/triage`
OTCトリアージフォーム（`otc_triage_form_screen.dart`）からのリクエスト。`triageResult` はサーバー側ロジックが決定し、AIの応答では変わらない。

```json
{
  "symptomCategory": "fever",
  "symptomQualities": ["発熱"],
  "severityScore": 2,
  "redFlags": { "veryHighFever40Plus": true, "consciousness": false },
  "egfr": 55.0,
  "medicineNames": []
}
```

## Flutter側との接続

`lib/services/ai_drug_service.dart` はデフォルトで `http://localhost:8081` を叩く(ローカル開発用のデフォルト値、変更不要)。
本番ビルドはCloud Run URLを`--dart-define`で上書きする(**本番URLはリポジトリに書かず、手元メモ/`.env`で管理**):

```bash
flutter build web --dart-define=LLM_PROXY_URL=https://<本番Cloud RunのURL>
```

**✅ 本番デプロイ・疎通確認済み(2026-07-20)**。本番Flutterビルドは既にこの方式でCloud Run URLを埋め込み済み。

プロキシに接続できない場合は、Flutter側でモック応答（服薬指導）またはレッドフラッグのみの簡易判定（トリアージ）にフォールバックする。

## Docker

```bash
docker build -t pharmacore-llm-proxy .
docker run -p 8080:8080 \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e FIREBASE_PROJECT_ID=pharmacist-app-646df \
  pharmacore-llm-proxy
```

マルチステージビルド（`golang:1.22-alpine` でビルド → `alpine:3.20` で実行）。標準ライブラリのみで外部Goモジュール依存がないため `go.sum` は存在しない。

**✅ 実機検証済み(2026-07-16)**: Docker Desktop 4.82.0 + WSL2導入後、`docker build` → `docker run` → `/healthz`・`/v1/triage` への実HTTPリクエストまで確認済み。

## 未実装・今後の課題

- **Cloud Run デプロイ**: ✅ 2026-07-20 本番デプロイ完了・稼働中(`asia-northeast1`、`min-instances=0`)。Firestore認証はSecret Managerにサービスアカウント鍵をボリュームマウントする方式(`GOOGLE_APPLICATION_CREDENTIALS`が既存コードの前提と一致するため、メタデータサーバー方式より変更が少なく済んだ)
- **`ANTHROPIC_API_KEY`**: 意図的に未設定のまま運用中。判定ロジック(`/v1/triage`, `/v1/analyze-medication`の薬剤ごとの注意点表示)はAPIキーなしで完全に機能する設計のため、契約は保留してもサービスは成立する。設定すればAI解説文・複数薬剤の重複統合機能が有効化される
- **料金定数の実値**: ✅ 2026-07-16 確認済み。claude-haiku-4-5 は Base Input $1/MTok、Output $5/MTok、Cache Write(5分) $1.25/MTok、Cache Read $0.10/MTok。モデル変更時は再確認すること
- **プロンプトキャッシュの実効性**: ✅ 2026-07-16確認。GA機能でbetaヘッダー不要だが、claude-haiku-4-5は最低4096トークンないとキャッシュされない。現状のシステムプロンプトは閾値未満のため、OTC症状ナレッジをシステムプロンプトに組み込むまでは実質無効
- **施設単位のトークン予算**: ✅ 実装済み（`facility_budget.go`）。施設ごとの上限＋全体の安全上限の二層構成
- **Dockerの実機検証**: ✅ ローカルDocker検証(2026-07-16)に加え、本番はDockerを介さず`gcloud builds submit`(Cloud Build)でビルド・Artifact Registryにプッシュしている
