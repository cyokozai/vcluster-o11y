// Pattern B: メインエントリポイント
//
// Pattern A と構造は同一。
// OTel SDK の向き先が OTel Collector ではなく Alloy になる点だけが異なる。
// OTel Collector を省略することで仮想クラスタ内のリソースを節約できる。

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	shutdown, err := initOtel(ctx)
	if err != nil {
		log.Fatalf("failed to initialize OTel: %v", err)
	}
	defer shutdown(context.Background())

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/health", handleHealth)

	handler := otelhttp.NewHandler(mux, "server02")

	port := getEnv("PORT", "8080")
	srv := &http.Server{Addr: ":" + port, Handler: handler}

	go func() {
		log.Printf("[Pattern B] server02 listening on :%s → Alloy at %s",
			port, getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "alloy:4317"))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("shutting down server02...")
	srv.Shutdown(context.Background())
}
