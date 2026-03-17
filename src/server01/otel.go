// Pattern A: OTel Collector あり
//
// テレメトリフロー:
//   Go API Server (OTel SDK)
//     → OTLP gRPC → OTel Collector (otel-collector:4317) ← 仮想クラスタ内に同居
//       → OTLP gRPC → Alloy (alloy:4317) ← replicateServices で複製
//         → Tempo / Prometheus / Loki
//
// OTel Collector を挟む利点:
//   - Collector 側でバッファリング・リトライ・変換を担う
//   - アプリが直接バックエンドに依存しないため移行が容易
//   - 受信プロトコルを複数に対応させやすい (gRPC / HTTP / Jaeger 等)

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

// newResource はサービス名などのリソース属性を定義する。
// Resource はどのサービスが発したテレメトリかをバックエンドで識別するために使われる。
func newResource() *resource.Resource {
	res, _ := resource.Merge(
		resource.Default(), // Go ランタイム情報 (バージョン等) を含むデフォルト属性
		resource.NewWithAttributes(
			semconv.SchemaURL,
			// OTEL_SERVICE_NAME 環境変数でサービス名を注入する
			// Grafana ダッシュボードの service_name ラベルに対応
			semconv.ServiceName(getEnv("OTEL_SERVICE_NAME", "server01-pattern-a")),
		),
	)
	return res
}

// initOtel は以下の 3 つのプロバイダーを初期化してグローバルに設定する。
//
//   - TracerProvider : トレース (分散トレーシング)
//   - MeterProvider  : メトリクス (Prometheus 互換)
//   - LoggerProvider : ログ (Loki へ転送)
//
// 全て同一の gRPC コネクションを使って OTel Collector に送信する。
func initOtel(ctx context.Context) (shutdown func(context.Context) error, err error) {
	// Pattern A: 送信先は仮想クラスタ内の OTel Collector
	// OTel Collector がバッファリングしてから Alloy へ転送する
	endpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")

	// gRPC コネクションを確立 (TLS なし: クラスタ内通信のため)
	conn, err := grpc.NewClient(
		endpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, err
	}

	res := newResource()

	// --- 1. TracerProvider: 分散トレースのプロバイダー ---
	// WithBatcher: スパンをバッチで送信し、ネットワーク負荷を下げる
	traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	// --- 2. MeterProvider: メトリクスのプロバイダー ---
	// NewPeriodicReader: 一定間隔 (デフォルト 60s) でメトリクスをエクスポートする
	metricExporter, err := otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	// --- 3. LoggerProvider: 構造化ログのプロバイダー ---
	// NewBatchProcessor: ログをバッチで送信する
	logExporter, err := otlploggrpc.New(ctx, otlploggrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)),
		sdklog.WithResource(res),
	)
	global.SetLoggerProvider(lp)

	// 全プロバイダーをシャットダウンする関数を返す
	// defer shutdown(ctx) で呼び出し、バッファされたデータを確実にフラッシュする
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
