package main

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/log/global"
)

var tracer = otel.Tracer("go-api-server")

func handleRoot(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "handle-root")
	defer span.End()

	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.path", r.URL.Path),
	)

	var rec otellog.Record
	rec.SetSeverity(otellog.SeverityInfo)
	rec.SetBody(otellog.StringValue("handling GET /"))
	global.GetLoggerProvider().Logger("go-api-server").Emit(ctx, rec)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Hello from go-api-server",
	})
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func handleMetrics() http.Handler {
	return promhttp.Handler()
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")
	statusCode, err := strconv.Atoi(code)
	if err != nil || statusCode < 100 || statusCode > 599 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid status code"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  statusCode,
		"message": http.StatusText(statusCode),
	})
}
