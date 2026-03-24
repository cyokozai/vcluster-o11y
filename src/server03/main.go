// Pattern C: Beyla (eBPF) 自動計装への移行後
//
// 変更前: Prometheus クライアントで /metrics を公開し Alloy が Pull scrape
// 変更後: Beyla DaemonSet が HTTP メトリクスを eBPF で自動収集し Alloy へ Push
//
// Prometheus クライアント依存を完全に除去し、
// アプリはビジネスロジックのみに集中できる。

package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

func handleRoot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Hello from server03 (Pattern C)",
	})
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/health", handleHealth)

	port := getEnv("PORT", "8080")
	log.Printf("[Pattern C] server03 listening on :%s", port)

	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
