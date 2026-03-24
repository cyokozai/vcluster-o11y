# Pattern B: OTel SDK (Alloy 直接送信)
#
# 使い方:
#   docker build --target dev -t server02:dev .
#   docker build -t server02:latest .
#   docker run --rm -p 8080:8080 \
#     -e OTEL_SERVICE_NAME=server02-pattern-b \
#     -e OTEL_EXPORTER_OTLP_ENDPOINT=alloy:4317 \
#     server02:latest
FROM golang:1.26 AS dev

WORKDIR /app

COPY go.mod ./
COPY *.go ./

RUN go mod tidy

EXPOSE 8080
CMD ["go", "run", "."]

FROM dev AS builder

RUN CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /server .

FROM gcr.io/distroless/static:nonroot AS runtime

COPY --from=builder /server /server

EXPOSE 8080

ENTRYPOINT ["/server"]
