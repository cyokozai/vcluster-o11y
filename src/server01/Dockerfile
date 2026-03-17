# Pattern A: OTel SDK + OTel Collector 構成
#
# 使い方:
#   docker build --target dev -t server01:dev .    # 開発環境 (bash 利用可)
#   docker build -t server01:latest .              # 本番イメージ
#   docker run --rm -p 8080:8080 \
#     -e OTEL_SERVICE_NAME=server01-pattern-a \
#     -e OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317 \
#     server01:latest

# ---- Stage 1: dev ----
# - golang:1.26 を使うため Go ツールチェーン・bash が利用可能
# - go mod tidy をコンテナ内で実行して go.sum を生成する
# - docker build --target dev でこのステージのイメージを使った開発が可能
FROM golang:1.26 AS dev

WORKDIR /app

COPY go.mod ./
COPY *.go ./

# go mod tidy: インポート解析 → 不足モジュール取得 → go.sum 生成
# (ローカルでは実行しない。コンテナ内でのみ実行する)
RUN go mod tidy

EXPOSE 8080
CMD ["go", "run", "."]

# ---- Stage 2: builder ----
# dev ステージをベースに静的リンクのバイナリをビルドする
FROM dev AS builder

RUN CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /server .

# ---- Stage 3: runtime ----
# distroless: シェルなし・パッケージマネージャなしの最小イメージ
# nonroot ユーザーで実行するためセキュリティリスクを低減する
FROM gcr.io/distroless/static:nonroot AS runtime

COPY --from=builder /server /server

EXPOSE 8080

ENTRYPOINT ["/server"]
