# Helmfile による各種リソースのインストール

## helmfile 経由でカスタムリソースをインストール

| コンポーネント | Chart | バージョン | Namespace |
| --- | --- | --- | --- |
| **Alloy** | grafana/alloy | 0.5.0 | monitoring |
| **Tempo** | grafana/tempo | 1.24.3 | monitoring |
| **Loki** | grafana/loki | 6.52.0 | monitoring |
| **kube-prometheus-stack** | prometheus-community/kube-prometheus-stack | 80.2.0 | monitoring |
| **vCluster** | loft/vcluster | 0.30.4 | vcluster-system |

## 検証

| コンポーネント | 役割 |
| --- | --- |
| **Alloy** | OTLP Receiver (メトリクス・トレース・ログ受信) → Tempo (トレース) / Prometheus Remote Write (メトリクス) / Loki (ログ) へ転送 |
| **Tempo** | Trace データの保存・検索 |
| **Loki** | ログデータの保存・検索 |
| **Prometheus (kube-prometheus-stack)** | メトリクス監視 (エラーレート可視化) |
| **Grafana (kube-prometheus-stack)** | Tempo / Loki の DataSource 追加済み |

## Resources

- vCluster
  - [GitHub](https://github.com/loft-sh/vcluster)
  - [Artifact Hub](https://artifacthub.io/packages/helm/loft/vcluster)
- kube-prometheus-stack
  - [GitHub](http://github.com/prometheus-operator/kube-prometheus)
  - [Artifact Hub](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
- Grafana Alloy
  - [GitHub](https://github.com/grafana/alloy)
  - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/alloy)
- Grafana Loki
  - [GitHub](https://github.com/grafana/loki)
  - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/loki)
- Grafana Tempo
  - [GitHub](https://github.com/grafana/tempo)
  - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/tempo)

## Install

### 1. ホストクラスタへの監視スタックのデプロイ

1. Helm リポジトリを登録

    ```bash
    helmfile repos -f helm/helmfile.yaml
    helm repo update
    ```

1. ホストクラスタに監視スタックをデプロイ

    ```bash
    helmfile sync -f helm/helmfile.yaml
    ```

### 2. 仮想クラスタの構築とデモアプリのデプロイ

1. 仮想クラスタを作成

    ```bash
    vcluster create otel-demo \
      --namespace vcluster-otel-demo \
      --upgrade \
      --values manifests/vcluster/config.yaml
    ```

    > クラスタ作成後、kubectl のコンテキストが自動で仮想クラスタに切り替わる

1. デモアプリ (OpenTelemetry Demo) を仮想クラスタにデプロイ

    ```bash
    helmfile sync -f helm/demo-otel.yaml
    ```

## Usage

- Prometheus
  - <http://localhost:9090/>

    ```bash
    kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
    ```

- Grafana
  - <http://localhost:3000/>

    ```bash
    kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
    ```

- vCluster

    ```bash
    vcluster list
    ```

## Uninstall

```bash
helmfile destroy -f helm/helmfile.yaml
vcluster delete otel-demo --namespace vcluster-otel-demo
```
