# 仮想クラスタの検証環境構築と検証作業

1. move `manifest` directory

  ```bash
  cd manifest
  ```

## 3\.1 検証用仮想クラスタを作成 (単一)

1. vCluster コマンドで仮想クラスタを作成

  ```bash
  vcluster create demo-cluster --namespace demo-cluster
  ```

1. クラスタが作成されると kubectl のクレデンシャルが自動で仮想クラスタ `demo-cluster` に切り替わる

  ```bash
  kubectl cluster-info
  ```

## 3\.2 検証用仮想クラスタを作成 (複数)

1. vCluster コマンドで仮想クラスタを作成

  ```bash
  vcluster create demo-cluster-0 --namespace demo-cluster-0 --values vclusterconfig/vcluster-cilium.yaml --connect=false
  vcluster create demo-cluster-1 --namespace demo-cluster-1 --values vclusterconfig/vcluster-cilium.yaml --connect=false
  vcluster create demo-cluster-2 --namespace demo-cluster-2 --values vclusterconfig/vcluster-cilium.yaml --connect=false
  ```

1. 作成したクラスタを確認

  ```bash
  vcluster list
  ```

  - 出力結果
  
    ```bash
           NAME      |    NAMESPACE    | STATUS  | VERSION | CONNECTED | AGE  
    -----------------+-----------------+---------+---------+-----------+------
      demo-cluster-0 | demo-cluster-0  | Running | 0.30.2  |           | 64s  
      demo-cluster-1 | demo-cluster-1  | Running | 0.30.2  |           | 61s  
      demo-cluster-2 | demo-cluster-2  | Running | 0.30.2  |           | 58s  
      vcluster       | vcluster-system | Running | 0.30.3  |           | 24m
    ```

1. 各仮想クラスタのクレデンシャルを取得する

  ```bash
  # demo-cluster-0 の場合
  vcluster connect demo-cluster-0
  vcluster disconnect
  ```

1. 各仮想クラスタに Cilium をインストールし、ネットワークを開通させる

  ```bash
  helmfile -f ../helm/cilium.yaml.gotmpl -e demo-cluster-0 sync
  helmfile -f ../helm/cilium.yaml.gotmpl -e demo-cluster-1 sync
  helmfile -f ../helm/cilium.yaml.gotmpl -e demo-cluster-2 sync
  ```

1. Cluster 0 から 1へ接続

  ```bash
  cilium clustermesh connect --context "vcluster_demo-cluster-0_demo-cluster-0_${EKSCONTEXT}" --destination-context "vcluster_demo-cluster-1_demo-cluster-1_${EKSCONTEXT}"
  ```

1. Cluster 0 から 2へ接続

  ```bash
  cilium clustermesh connect --context "vcluster_demo-cluster-0_demo-cluster-0_${EKSCONTEXT}" --destination-context "vcluster_demo-cluster-2_demo-cluster-2_${EKSCONTEXT}"
  ```

1. Cluster 1 から 2へ接続

  ```bash
  cilium clustermesh connect --context "vcluster_demo-cluster-1_demo-cluster-1_${EKSCONTEXT}" --destination-context "vcluster_demo-cluster-2_demo-cluster-2_${EKSCONTEXT}"
  ```

1. Cluster 0 のステータス確認

  ```bash
  cilium clustermesh status --context "vcluster_demo-cluster-0_demo-cluster-0_${EKSCONTEXT}"
  ```

 - 出力結果

    ```bash
    
    ```

- 検証用アプリケーションを各仮想クラスタへインストール

  ```bash
  helmfile -f ../helm/demo-boutique.yaml.gotmpl sync
  ```
