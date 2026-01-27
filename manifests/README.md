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

## 3\.2 検証用仮想クラスタを作成 (複数)

1. vCluster コマンドで仮想クラスタを作成

    - `demo-cluster-0`

        ```bash
        vcluster create demo-cluster-0 --namespace demo-cluster-0 \
            --values vclusterconfig/vcluster-cilium.yaml \
            --set sync.fromHost.nodes.selector.labels.vcluster=demo-cluster-0 \
            --set controlPlane.statefulSet.scheduling.nodeSelector.vcluster=demo-cluster-0
        vcluster disconnect
        ```

    - `demo-cluster-1`

        ```bash
        vcluster create demo-cluster-1 --namespace demo-cluster-1 \
            --values vclusterconfig/vcluster-cilium.yaml \
            --set sync.fromHost.nodes.selector.labels.vcluster=demo-cluster-1 \
            --set controlPlane.statefulSet.scheduling.nodeSelector.vcluster=demo-cluster-1
        vcluster disconnect
        ```

    - `demo-cluster-2`

        ```bash
        vcluster create demo-cluster-2 --namespace demo-cluster-2 \
            --values vclusterconfig/vcluster-cilium.yaml \
            --set sync.fromHost.nodes.selector.labels.vcluster=demo-cluster-2 \
            --set controlPlane.statefulSet.scheduling.nodeSelector.vcluster=demo-cluster-2
        vcluster disconnect
        ```

    ```mermaid
    graph LR
        subgraph Local Mac
            A[kubectl / Helm] -->|1. アクセス| B(Local Proxy Container)
            B -.->|2. ポートフォワード| A
        end

        subgraph Internet
            B == 3. Kubernetes API ==> C[AWS EKS Cluster]
        end

        subgraph AWS EKS Node
            C --> D[vCluster Pod]
            D --> E[vCluster API Server]
        end
    ```

2. 作成したクラスタを確認

    ```bash
    vcluster list
    ```

    - 出力結果

      ```bash
             NAME      |    NAMESPACE    | STATUS  | VERSION | CONNECTED | AGE  
      -----------------+-----------------+---------+---------+-----------+------
        demo-cluster-0 | demo-cluster-0  | Running | 0.30.3  |           | 64s  
        demo-cluster-1 | demo-cluster-1  | Running | 0.30.3  |           | 61s  
        demo-cluster-2 | demo-cluster-2  | Running | 0.30.3  |           | 58s  
        vcluster       | vcluster-system | Running | 0.30.3  |           | 24m
      ```

3. 各仮想クラスタに Cilium をインストールし、ネットワークを開通させる

    ```bash
    helmfile sync -f ../helm/cilium.yaml.gotmpl -e demo-cluster-0
    helmfile sync -f ../helm/cilium.yaml.gotmpl -e demo-cluster-1
    helmfile sync -f ../helm/cilium.yaml.gotmpl -e demo-cluster-2
    ```

4. Cluster 0 から 1へ接続

    ```bash
    cilium clustermesh connect --context "vcluster_demo-cluster-0_demo-cluster-0_${DEV_KUBE_CONTEXT}" --destination-context "vcluster_demo-cluster-1_demo-cluster-1_${DEV_KUBE_CONTEXT}"
    ```

5. Cluster 0 から 2へ接続

    ```bash
    cilium clustermesh connect --context "vcluster_demo-cluster-0_demo-cluster-0_${DEV_KUBE_CONTEXT}" --destination-context "vcluster_demo-cluster-2_demo-cluster-2_${DEV_KUBE_CONTEXT}"
    ```

6. Cluster 1 から 2へ接続

    ```bash
    cilium clustermesh connect --context "vcluster_demo-cluster-1_demo-cluster-1_${DEV_KUBE_CONTEXT}" --destination-context "vcluster_demo-cluster-2_demo-cluster-2_${DEV_KUBE_CONTEXT}"
    ```

7. Cluster 0 のステータス確認

    ```bash
    cilium clustermesh status --context "vcluster_demo-cluster-0_demo-cluster-0_${DEV_KUBE_CONTEXT}"
    ```
    
    - 出力結果

      ```bash
      
      ```

8. 検証用アプリケーションを各仮想クラスタへインストール

    ```bash
    helmfile -f ../helm/demo-boutique.yaml.gotmpl sync
    ```
  
---

1. 仮想クラスタの削除

    ```bash
    vcluster delete demo-cluster-0
    vcluster delete demo-cluster-1
    vcluster delete demo-cluster-2
    ```
