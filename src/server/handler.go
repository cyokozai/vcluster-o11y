package main

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func handleRoot(w http.ResponseWriter, _ *http.Request) {
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
