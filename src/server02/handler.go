// Pattern A/B 共通: HTTPハンドラ (server02 版)
// コードは server01/handler.go と同一。
// Pattern A と B の違いはコードではなく「OTel SDK が接続する先」だけ。
//   Pattern A: otel-collector:4317 (仮想クラスタ内の OTel Collector)
//   Pattern B: alloy:4317          (replicateServices で複製された Alloy)

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

var tracer = otel.Tracer("server02")

func emitLog(ctx context.Context, severity otellog.Severity, msg string, attrs ...otellog.KeyValue) {
	var rec otellog.Record
	rec.SetSeverity(severity)
	rec.SetBody(otellog.StringValue(msg))
	rec.AddAttributes(attrs...)
	global.GetLoggerProvider().Logger("server02").Emit(ctx, rec)
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "handle-root")
	defer span.End()

	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.path", r.URL.Path),
	)
	emitLog(ctx, otellog.SeverityInfo, "handling GET /",
		otellog.String("http.method", r.Method),
		otellog.String("http.path", r.URL.Path),
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Hello from server02 (Pattern B)",
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
