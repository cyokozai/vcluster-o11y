// Pattern A: メインエントリポイント
//
// OTel SDK を初期化してから HTTP サーバーを起動する。
// otelhttp.NewHandler でルーター全体をラップすることで、
// 全エンドポイントへのリクエストを自動的に計装する。

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	// otelhttp: net/http を自動計装するミドルウェア
	// リクエストごとに親スパンを生成し、ハンドラに Context を伝播する
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	// SIGINT (Ctrl+C) / SIGTERM (kubectl delete pod) でグレースフルシャットダウン
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// OTel SDK 初期化: Trace / Metric / Log の 3 プロバイダーを起動する
	shutdown, err := initOtel(ctx)
	if err != nil {
		log.Fatalf("failed to initialize OTel: %v", err)
	}
	// プロセス終了時にバッファされたテレメトリをフラッシュしてから閉じる。
	// shutdown がハングしないように、タイムアウト付きの Context を使う。
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdown(shutdownCtx); err != nil {
			log.Printf("failed to shutdown OTel SDK: %v", err)
		}
	}()

	// ルーターの登録
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/health", handleHealth)

	// otelhttp.NewHandler でルーター全体を OTel ミドルウェアでラップする。
	// これにより:
	//   - 各リクエストに span が自動生成される
	//   - span は w3c trace context ヘッダーを使って伝播される
	//   - http.request.duration などの HTTP メトリクスが自動計測される
	handler := otelhttp.NewHandler(mux, "server01")

	port := getEnv("PORT", "8080")
	srv := &http.Server{Addr: ":" + port, Handler: handler}

	go func() {
		log.Printf("[Pattern A] server01 listening on :%s → OTel Collector at %s",
			port, getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317"))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	// シグナルを受信するまでブロック
	<-ctx.Done()
	log.Println("shutting down server01...")
	// 一定時間でタイムアウトするコンテキストを使ってグレースフルシャットダウン
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("server shutdown error: %v", err)
	}
}
