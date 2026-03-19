# Helmfile による各種コンポーネントのインストール

## helmfile 経由でコンポーネントをインストール

| コンポーネント | Chart | バージョン | Namespace |
| --- | --- | --- | --- |
| **Alloy** | grafana/alloy | 1.6.1 | monitoring |
| **Tempo** | grafana/tempo | 1.24.4 | monitoring |
| **Loki** | grafana/loki | 6.53.0 | monitoring |
| **kube-prometheus-stack** | prometheus-community/kube-prometheus-stack | 82.10.1 | monitoring |
| **vCluster** | loft/vcluster | 0.32.1 | vcluster-system |

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

1. Grafana アラートルールを適用

    ```bash
    kubectl apply -f manifests/monitoring/grafana-alert-rules.yaml
    ```

1. Grafana ダッシュボードを適用

    ```bash
    kubectl apply -f manifests/monitoring/grafana-dashboards.yaml
    ```

    > `grafana.sidecar.dashboards` が ConfigMap を検知し、Grafana に自動ロードされる

### 2. 仮想クラスタの構築とデモアプリのデプロイ

実施する検証内容（検証1 または 検証2）に合わせて、以下のいずれかの手順で仮想クラスタを構築・アプリをデプロイしてください。

#### 検証1: OTel Demo を用いたテレメトリパイプラインの動作検証 の場合

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

#### 検証2: 複数 vCluster の一元監視 の場合

1. 3つの仮想クラスタ (`vcluster-1`, `vcluster-2`, `vcluster-3`) を作成

    ```bash
    # vcluster-1 (Pattern A)
    kubectl create namespace vcluster-1
    vcluster create vcluster-1 -n vcluster-1

    # vcluster-2 (Pattern B)
    kubectl create namespace vcluster-2
    vcluster create vcluster-2 -n vcluster-2

    # vcluster-3 (Pattern C)
    kubectl create namespace vcluster-3
    vcluster create vcluster-3 -n vcluster-3
    ```

    > クラスタ作成後、kubectl のコンテキストが自動で直近に作成した仮想クラスタに切り替わります。

1. 各仮想クラスタへアプリをデプロイ

    コンテナイメージのビルドとプッシュが完了していることを前提としています。

    ```bash
    # Pattern A のデプロイ (vcluster-1)
    vcluster connect vcluster-1 -n vcluster-1
    kubectl apply -f manifests/vcluster/pattern-a/otel-collector.yaml
    kubectl apply -f manifests/vcluster/pattern-a/api-server.yaml
    vcluster disconnect

    # Pattern B のデプロイ (vcluster-2)
    vcluster connect vcluster-2 -n vcluster-2
    kubectl apply -f manifests/vcluster/pattern-b/api-server.yaml
    vcluster disconnect

    # Pattern C のデプロイ (vcluster-3)
    vcluster connect vcluster-3 -n vcluster-3
    kubectl apply -f manifests/vcluster/pattern-c/api-server.yaml
    vcluster disconnect
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

  - ログイン情報: ユーザー名 `admin`、パスワードは Secret から取得

    ```bash
    export PASSWORD=$(kubectl get secret kube-prometheus-stack-grafana -n monitoring \
      -o jsonpath="{.data.admin-password}" | base64 --decode)
    echo $PASSWORD
    ```

- vCluster

    ```bash
    vcluster list
    ```

## Uninstall

```bash
# ホストクラスタの監視スタックを削除
helmfile destroy -f helm/helmfile.yaml

# 検証1の仮想クラスタを削除する場合
vcluster delete otel-demo --namespace vcluster-otel-demo

# 検証2の仮想クラスタを削除する場合
vcluster delete vcluster-1 --namespace vcluster-1
vcluster delete vcluster-2 --namespace vcluster-2
vcluster delete vcluster-3 --namespace vcluster-3
```
