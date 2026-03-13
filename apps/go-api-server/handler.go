package main

import (
	"encoding/json"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
)

var tracer = otel.Tracer("go-api-server")

func handleRoot(w http.ResponseWriter, r *http.Request) {
	_, span := tracer.Start(r.Context(), "handle-root")
	defer span.End()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Hello from go-api-server"})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	_, span := tracer.Start(r.Context(), "handle-health")
	defer span.End()

	span.SetAttributes(attribute.String("status", "ok"))
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
