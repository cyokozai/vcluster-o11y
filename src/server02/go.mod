module github.com/vcluster-o11y/server02

go 1.26

// Pattern B の依存: OTel SDK フル構成 (Pattern A と同じ)
// Pattern B の特徴は「Collector を挟まない」という構成であり、
// コード自体は Pattern A と同一で環境変数の向き先のみ異なる。
require (
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.59.0
	go.opentelemetry.io/otel v1.34.0
	go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc v0.10.0
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc v1.34.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.34.0
	go.opentelemetry.io/otel/log v0.10.0
	go.opentelemetry.io/otel/sdk v1.34.0
	go.opentelemetry.io/otel/sdk/log v0.10.0
	go.opentelemetry.io/otel/sdk/metric v1.34.0
	google.golang.org/grpc v1.71.0
)
