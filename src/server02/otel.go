// Pattern B: OTel Collector なし (OTel SDK → Alloy 直接)
//
// テレメトリフロー:
//   Go API Server (OTel SDK)
//     → OTLP gRPC → Alloy (alloy:4317) ← replicateServices で複製
//       → Tempo / Prometheus / Loki
//
// Pattern A との違い:
//   - OTel Collector を仮想クラスタ内にデプロイしない
//   - アプリが Alloy に直接 OTLP を送信する
//   - 運用コストが低い (Collector の設定・管理が不要)
//   - バッファリングは Alloy が担う
//   - ただし変換処理 (フィルタ、属性追加等) は Alloy の設定で行う必要がある

package main

import (
	"context"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/log/global"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func newResource() *resource.Resource {
	res, _ := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(getEnv("OTEL_SERVICE_NAME", "server02-pattern-b")),
		),
	)
	return res
}

func initOtel(ctx context.Context) (shutdown func(context.Context) error, err error) {
	// Pattern B: 送信先は replicateServices で複製された Alloy Service
	// vCluster の `fromHost` 設定により、ホスト側の Alloy が
	// 仮想クラスタ内に `alloy` という名前で複製されている
	endpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "alloy:4317")

	conn, err := grpc.NewClient(
		endpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, err
	}
	// exporter 初期化中にエラーが発生した場合、conn をCloseしてリークを防ぐ
	defer func() {
		if err != nil {
			_ = conn.Close()
		}
	}()

	res := newResource()

	// Trace, Metric, Log の 3 プロバイダーを初期化する
	// 構造は Pattern A と完全に同一 — 差異は endpoint の向き先のみ

	traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	metricExporter, err := otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	logExporter, err := otlploggrpc.New(ctx, otlploggrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)),
		sdklog.WithResource(res),
	)
	global.SetLoggerProvider(lp)

	return func(ctx context.Context) error {
		_ = tp.Shutdown(ctx)
		_ = mp.Shutdown(ctx)
		_ = lp.Shutdown(ctx)
		return conn.Close()
	}, nil
}

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}
