# マルチステージビルド: ビルド専用イメージでコンパイルし、実行イメージには
# 静的リンクされたバイナリのみをコピーする(distroless相当の最小構成)。
FROM golang:1.22-alpine AS builder

WORKDIR /src

# 依存モジュールのキャッシュを効かせるため go.mod/go.sum を先にコピー
# (このプロジェクトは標準ライブラリのみで外部依存がないため go.sum は存在しない)
COPY go.mod ./
RUN go mod download

COPY . .

# CGO無効・静的リンクでビルド。Cloud Run(distroless系ベースイメージ)でもそのまま動く。
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/llm-proxy .

# 実行イメージ: 証明書検証(Anthropic API・Firebase公開鍵取得)に必要なCA証明書のみ追加
FROM alpine:3.20

RUN apk add --no-cache ca-certificates

COPY --from=builder /out/llm-proxy /usr/local/bin/llm-proxy

# Cloud Run は PORT 環境変数でリッスンポートを指定してくる。main.go はこれを読む。
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/llm-proxy"]
