// Pattern C: Prometheus scrape のみ
//
// テレメトリフロー:
//   Alloy (ホストクラスタ)
//     → HTTP scrape → go-api-server.vcluster-3.svc:8080/metrics ← toHost で公開
//       → prometheus.remote_write → Prometheus
//
// このパターンの特徴:
//   - OTel SDK を一切使わない (依存が大幅に減る)
//   - Prometheus クライアントで /metrics エンドポイントを公開する
//   - Alloy がホスト側から定期的に scrape に来る (Push ではなく Pull モデル)
//   - トレースとログは取得できない (メトリクスのみ)
//   - 既存のアプリに最小限の変更で監視を追加したいときに有効
//
// Prometheus メトリクスの種類:
//   Counter   : 単調増加する累積カウント (リクエスト総数、エラー数 など)
//   Gauge     : 任意に増減する現在値 (メモリ使用量、同時接続数 など)
//   Histogram : 値の分布を計測 (レイテンシのパーセンタイル など)
//   Summary   : Histogram に近いが quantile をクライアント側で計算する

package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// --- カスタムメトリクスの定義 ---
//
// promauto.New* を使うとデフォルトの Registerer (DefaultRegisterer) に
// 自動登録され、promhttp.Handler() が自動的に収集してくれる。

var (
	// httpRequestsTotal: リクエスト総数を path / method / status_code で分類する Counter
	// Grafana での PromQL 例:
	//   rate(http_requests_total{job="server03"}[1m])  → リクエストレート
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"path", "method", "status_code"},
	)

	// httpRequestDuration: リクエスト処理時間の分布を計測する Histogram
	// Grafana での PromQL 例:
	//   histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))  → P99 レイテンシ
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets, // .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10
		},
		[]string{"path", "method"},
	)
)

// instrumentedHandler は各ハンドラをラップしてメトリクスを记录する。
// Pattern A/B の otelhttp.NewHandler に相当するが、Prometheus 版。
func instrumentedHandler(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 処理時間計測の開始
		start := time.Now()

		// ResponseWriter をラップしてステータスコードを捕捉する
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next(rw, r)

		// メトリクスを記録する
		duration := time.Since(start).Seconds()
		statusCode := strconv.Itoa(rw.statusCode)

		httpRequestsTotal.WithLabelValues(path, r.Method, statusCode).Inc()
		httpRequestDuration.WithLabelValues(path, r.Method).Observe(duration)
	}
}

// responseWriter はステータスコードを記録するための http.ResponseWriter ラッパー。
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

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

	// 各ハンドラを instrumentedHandler でラップしてメトリクスを収集する
	mux.HandleFunc("/", instrumentedHandler("/", handleRoot))
	mux.HandleFunc("/health", instrumentedHandler("/health", handleHealth))

	// /metrics エンドポイント: Alloy が scrape するエンドポイント
	// promhttp.Handler() はデフォルトの Gatherer からメトリクスを収集して返す。
	// 含まれるメトリクス:
	//   - カスタム: http_requests_total, http_request_duration_seconds
	//   - デフォルト: go_*, process_* (Go ランタイム、プロセスの各種統計)
	mux.Handle("/metrics", promhttp.Handler())

	port := getEnv("PORT", "8080")
	log.Printf("[Pattern C] server03 listening on :%s (Prometheus scrape only, no OTel SDK)", port)

	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
