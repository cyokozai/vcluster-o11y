# go-api-server

OTel SDK (Go) を組み込んだ HTTP サーバです．Pattern A / B の計装サンプルサーバとして使用します．

## エンドポイント

| パス | 説明 |
| --- | --- |
| `GET /` | JSON レスポンスを返す（トレース・ログを生成） |
| `GET /health` | ヘルスチェック |
| `GET /status/:code` | 指定したステータスコードを返す（例: `/status/500`） |

## 環境変数

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `PORT` | `8080` | リッスンポート |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | OTLP エクスポート先（例: `otelcol:4317`） |
| `OTEL_SERVICE_NAME` | — | Prometheus の `job` ラベルになる |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | — | `grpc` または `http/protobuf` |

## ローカル実行

```bash
cd src/server/

OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4317 \
OTEL_SERVICE_NAME=go-api-server-local \
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
go run .
```

## Docker イメージのビルドと ECR へのプッシュ

```bash
# 変数を設定
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/go-api-server"

# ECR にログイン
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ビルド（マルチステージ: runtime ステージのみ）
docker build --target runtime \
  -t "${ECR_REPO}:latest" \
  src/server/

# プッシュ
docker push "${ECR_REPO}:latest"
```

> **注意**: `manifests/pattern-*/deploy.yaml` のイメージ参照（`image:` フィールド）を上記 `$ECR_REPO` に合わせて変更してください．

## マルチアーキテクチャビルド (Apple Silicon 等)

EKS ノード (x86_64) に対して Mac (arm64) からビルドする場合:

```bash
docker buildx build --platform linux/amd64 \
  --target runtime \
  -t "${ECR_REPO}:latest" \
  --push \
  src/server/
```
