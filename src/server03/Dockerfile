# Pattern C: Prometheus scrape のみ (OTel SDK なし)
#
# 依存が少ないため go mod tidy の実行が速く、ビルドが軽量。
#
# 使い方:
#   docker build --target dev -t server03:dev .    # 開発環境
#   docker build -t server03:latest .              # 本番イメージ
#   docker run --rm -p 8080:8080 server03:latest
#
#   # /metrics が Prometheus 形式で返ることを確認
#   curl http://localhost:8080/metrics

FROM golang:1.26 AS dev

WORKDIR /app

COPY go.mod ./
COPY *.go ./

# OTel SDK がないため go mod tidy は高速に完了する
RUN go mod tidy

EXPOSE 8080
CMD ["go", "run", "."]

FROM dev AS builder

RUN CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /server .

FROM gcr.io/distroless/static:nonroot AS runtime

COPY --from=builder /server /server

EXPOSE 8080

ENTRYPOINT ["/server"]
