# vCluster と Grafana Alloy によるマルチテナント Kubernetes オブザーバビリティ基盤

単一の AWS EKS クラスタ上に vCluster で仮想クラスタ（テナント）を構築し，Grafana Alloy を集約ゲートウェイとしてメトリクス／トレース／ログを一元管理するオブザーバビリティ基盤です．

## アーキテクチャ

```mermaid
flowchart TB
  subgraph vc1["vcluster-1 (Pattern A: OTel Collector あり)"]
    app1["Go API Server (OTel SDK)"]
    col1["OTel Collector"]
    app1 -->|"OTLP gRPC :4317"| col1
  end

  subgraph vc2["vcluster-2 (Pattern B: OTel Collector なし)"]
    app2["Go API Server (OTel SDK)"]
  end

  subgraph vc3["vcluster-3 (Pattern C: Prometheus scrape)"]
    app3["Go API Server (/metrics)"]
  end

  subgraph host["Host Cluster (monitoring namespace)"]
    alloy["Grafana Alloy"]
    prometheus["Prometheus"]
    tempo["Tempo"]
    loki["Loki"]
    grafana["Grafana"]

    alloy -->|"Remote Write"| prometheus
    alloy -->|"OTLP"| tempo
    alloy -->|"Loki Push"| loki
    prometheus & tempo & loki --> grafana
  end

  col1 -->|"OTLP (replicateServices)"| alloy
  app2 -->|"OTLP (replicateServices)"| alloy
  app3 -->|"/metrics (scrape)"| alloy
```

## コンポーネント一覧

| コンポーネント | バージョン | 役割 |
| --- | --- | --- |
| Terraform | 1.14.4 | EKS クラスタのプロビジョニング |
| Helm / Helmfile | 4.1.1 / 1.3.1 | Kubernetes コンポーネントのデプロイ管理 |
| kubectl | v1.35.1 (client) / v1.34.4-eks (server) | クラスタ操作 |
| vCluster / vCluster CLI | v0.32.1 | 仮想クラスタの作成・管理 |
| Grafana Alloy | v1.13.2 (chart 0.6.2) | OTLP 受信・テレメトリ転送ゲートウェイ |
| kube-prometheus-stack | 0.89.0 (chart 82.10.1) | Prometheus + Grafana によるメトリクス監視 |
| Loki | 3.6.5 (chart 6.53.0) | ログ収集・保存 |
| Tempo | 2.9.0 (chart 1.24.4) | 分散トレース収集・Service Map |
| OpenTelemetry Demo | 2.2.0 (chart 0.40.5) | 検証用デモアプリ |

## ディレクトリ構成

```
.
├── terraform/          # EKS クラスタ (IaC)
├── helm/
│   ├── helmfile.yaml   # ホストクラスタ監視スタック (Alloy / Tempo / Loki / kube-prometheus-stack / vCluster)
│   └── demo-otel.yaml  # 仮想クラスタ用 OpenTelemetry Demo
├── manifests/
│   ├── storageclass/   # gp3 StorageClass
│   ├── monitoring/     # Grafana アラートルール
│   ├── vcluster/       # vCluster 設定ファイル (config.yaml, vcluster-{1,2,3}-config.yaml)
│   ├── pattern-a/      # Go API Server + OTel Collector (OTLP → Alloy)
│   ├── pattern-b/      # Go API Server (OTel SDK 直接 → Alloy)
│   └── pattern-c/      # Go API Server (/metrics scrape)
└── src/
    └── server01/       # Go API Server ソースコード
```

## セットアップ手順

### 前提条件

- AWS CLI（認証済み）
- Terraform, Helm, Helmfile, kubectl, vCluster CLI がインストール済み

### 1. EKS クラスタの作成

```bash
cd terraform

# IAM ARN を使って tfvars を生成
echo "eks_access_entry_principal_arn = $(aws sts get-caller-identity --output json --no-cli-pager | jq '.Arn')" > terraform.tfvars

# 初期化
terraform init

# 計画・適用
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

### 2. kubeconfig の設定

```bash
export REGION="ap-northeast-1"
export CLUSTER_NAME="demo-eks-vcluster"

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
kubectl cluster-info
```

### 3. StorageClass の作成

```bash
cd ..
kubectl apply -f manifests/storageclass/gp3-storageclass.yaml
```

### 4. ホストクラスタへの監視スタックデプロイ

```bash
# Helm リポジトリ登録
helmfile repos -f helm/helmfile.yaml
helm repo update

# Alloy / Tempo / Loki / kube-prometheus-stack / vCluster をデプロイ
helmfile sync -f helm/helmfile.yaml

# Grafana アラートルールを適用
kubectl apply -f manifests/monitoring/grafana-alert-rules.yaml
```

### 5. 仮想クラスタの作成とデモアプリのデプロイ（検証 1）

```bash
# 仮想クラスタ otel-demo を作成 (コンテキストが自動で切り替わる)
vcluster create otel-demo \
  --namespace vcluster-otel-demo \
  --upgrade \
  --values manifests/vcluster/config.yaml

# Helm リポジトリ登録
helmfile repos -f helm/demo-otel.yaml
helm repo update

# OpenTelemetry Demo をデプロイ
helmfile sync -f helm/demo-otel.yaml

# ホストクラスタに戻る
vcluster disconnect
```

### 6. 仮想クラスタの作成（検証 2: Pattern A / B / C）

```bash
# Pattern A: OTel Collector あり
vcluster create vcluster-1 \
  --namespace vcluster-1 \
  --upgrade \
  --values manifests/vcluster/vcluster-1-config.yaml
kubectl apply -f manifests/pattern-a/deploy.yaml
vcluster disconnect

# Pattern B: OTel Collector なし
vcluster create vcluster-2 \
  --namespace vcluster-2 \
  --upgrade \
  --values manifests/vcluster/vcluster-2-config.yaml
kubectl apply -f manifests/pattern-b/deploy.yaml
vcluster disconnect

# Pattern C: Prometheus scrape
vcluster create vcluster-3 \
  --namespace vcluster-3 \
  --upgrade \
  --values manifests/vcluster/vcluster-3-config.yaml
kubectl apply -f manifests/pattern-c/deploy.yaml
vcluster disconnect
```

### 7. Grafana へのアクセス

```bash
# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# 管理者パスワードを取得
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode | pbcopy
```

ブラウザで http://localhost:3000 を開き，ユーザー名 `admin`・コピーしたパスワードでログイン．

### 8. クラスタの削除

```bash
vcluster delete otel-demo --namespace vcluster-otel-demo
vcluster delete vcluster-1 --namespace vcluster-1
vcluster delete vcluster-2 --namespace vcluster-2
vcluster delete vcluster-3 --namespace vcluster-3

cd terraform
terraform destroy -var-file="terraform.tfvars"
```

## テレメトリ収集パターンの比較

| | Pattern A | Pattern B | Pattern C |
| --- | --- | --- | --- |
| **OTel Collector** | あり | なし | なし |
| **OTel SDK** | あり | あり | なし |
| **Metrics** | ✓ (OTLP) | ✓ (OTLP) | ✓ (scrape) |
| **Traces** | ✓ | ✓ | ✗ |
| **Logs** | ✓ | ✓ | ✗ |
| **運用コスト** | 高 | 低 | 最低 |

## 参考資料

- [vCluster Docs](https://www.vcluster.com/docs/)
- [Grafana Alloy Docs](https://grafana.com/docs/alloy/)
- [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)
- [OpenTelemetry Go Instrumentation](https://opentelemetry.io/docs/languages/go/instrumentation/)
