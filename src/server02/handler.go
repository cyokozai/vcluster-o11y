// Pattern B: HTTP ハンドラ
//
// OTel SDK の手動計装を除去した純粋なビジネスロジック実装。
// トレース・メトリクスは Beyla (eBPF) が自動で収集する。

package main

import (
	"encoding/json"
	"net/http"
)

func handleRoot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Hello from server02 (Pattern B)",
	})
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
