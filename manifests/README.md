# 検証

- move `manifest` directory

  ```bash
  cd manifest
  ```

## 3\.1 検証用仮想クラスタを作成 (単一)

- vCluster コマンドで仮想クラスタを作成

  ```bash
  vcluster create demo-cluster --namespace demo-cluster
  ```

- クラスタが作成されると kubectl のクレデンシャルが自動で仮想クラスタ `demo-cluster` に切り替わる

  ```bash
  kubectl cluster-info
  ```

## 3\.2 検証用仮想クラスタを作成 (複数)

- vCluster コマンドで仮想クラスタを作成

  ```bash
  vcluster create demo-cluster-0 --namespace demo-cluster-0 --values vclusterconfig/vcluster-cilium.yaml --connect=false
  vcluster create demo-cluster-1 --namespace demo-cluster-1 --values vclusterconfig/vcluster-cilium.yaml --connect=false
  vcluster create demo-cluster-2 --namespace demo-cluster-2 --values vclusterconfig/vcluster-cilium.yaml --connect=false
  ```

- 作成したクラスタを確認

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

- 各仮想クラスタのクレデンシャルを取得する

  ```bash
  # demo-cluster-0 の場合
  vcluster connect demo-cluster-0
  vcluster disconnect
  ```

- 各仮想クラスタに Cilium をインストールし、ネットワークを開通させる

  ```bash
  helmfile -f ../helm/cilium.yaml.gotmpl sync
  ```
