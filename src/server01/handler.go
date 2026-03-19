// Pattern A/B 共通: HTTPハンドラ
//
// ハンドラの役割:
//   1. OTel Tracer でスパンを開始し、処理時間を計測する
//   2. OTel Logger で構造化ログを emit する (Loki に転送される)
//   3. レスポンスを返す

package main

import (
	"context"
	"encoding/json"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/log/global"
)

// tracer はパッケージレベル変数として保持する。
// otel.Tracer() はグローバルな TracerProvider からトレーサーを取得する。
var tracer = otel.Tracer("server01")

// emitLog はリクエストコンテキストに紐づけて構造化ログを emit するヘルパー。
// ctx を渡すことで、ログに現在のトレース ID が自動的に埋め込まれる。
// → Grafana で TraceID からログへの相関ジャンプが可能になる
func emitLog(ctx context.Context, severity otellog.Severity, msg string, attrs ...otellog.KeyValue) {
	var rec otellog.Record
	rec.SetSeverity(severity)
	rec.SetBody(otellog.StringValue(msg))
	rec.AddAttributes(attrs...)
	global.GetLoggerProvider().Logger("server01").Emit(ctx, rec)
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	// tracer.Start でスパンを開始し、defer span.End() で処理完了時に閉じる。
	// otelhttp.NewHandler (main.go) がリクエスト全体の親スパンを作るので
	// ここでは子スパンを作って処理の内訳を記録する。
	ctx, span := tracer.Start(r.Context(), "handle-root")
	defer span.End()

	// スパンに属性を付与する (Tempo の Trace 詳細画面で確認できる)
	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.path", r.URL.Path),
	)

	// 構造化ログを emit する
	// severity=Info, body がログのメッセージ本文, attrs がキーバリューのフィールド
	emitLog(ctx, otellog.SeverityInfo, "handling GET /",
		otellog.String("http.method", r.Method),
		otellog.String("http.path", r.URL.Path),
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Hello from server01 (Pattern A)",
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "handle-health")
	defer span.End()

	span.SetAttributes(attribute.String("status", "ok"))
	emitLog(ctx, otellog.SeverityInfo, "health check ok")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
