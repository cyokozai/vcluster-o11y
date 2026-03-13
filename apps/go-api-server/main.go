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

	handler := otelhttp.NewHandler(mux, "go-api-server")

	port := getEnv("PORT", "8080")
	srv := &http.Server{Addr: ":" + port, Handler: handler}

	go func() {
		log.Printf("server listening on :%s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("shutting down...")
	srv.Shutdown(context.Background())
}
