# EKS クラスタの構築

- クレデンシャルを取得

    ```shell
    aws eks update-kubeconfig --region <リージョン名> --name <クラスタ名>
    ```

- クラスタの確認

    ```shell
    kubectl cluster-info
    ```

- vCluster がインストールされていることを確認する

    ```shell
    ```

