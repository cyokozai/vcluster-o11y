module github.com/vcluster-o11y/server03

go 1.26

// Pattern C の依存: OTel SDK は不要。
// Prometheus クライアントで /metrics エンドポイントを公開するだけ。
// OTel SDK を使わないため依存が大幅にシンプルになる。
require (
	github.com/prometheus/client_golang v1.20.5
)
