# 仮想クラスタの検証環境構築と検証作業

## 3\.1 検証用仮想クラスタを作成 (単一)

1. vCluster コマンドで仮想クラスタを作成

    ```bash
    vcluster create otel-demo \
        --namespace vcluster-otel-demo \
        --values manifests/vcluster/config.yaml
    ```

1. クラスタが作成されると kubectl のクレデンシャルが自動で仮想クラスタ `demo-cluster` に切り替わる

    ```bash
    kubectl cluster-info
    ```

1. `helm/demo-otel.yaml` を仮想クラスタに適用して、デモアプリをデプロイする

    ```bash
    helmfile sync -f helm/demo-otel.yaml
    ```
  
---

1. 仮想クラスタの削除

    ```bash
    vcluster delete demo-cluster-0
    vcluster delete demo-cluster-1
    vcluster delete demo-cluster-2
    ```
