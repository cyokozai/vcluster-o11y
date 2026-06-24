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
