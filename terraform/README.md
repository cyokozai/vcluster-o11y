# EKS クラスタの構築

- Terraform 初期化を行う

    ```shell
    terraform init
    ```

- 構築を開始

    ```shell
    terraform apply
    ```

- クレデンシャルを取得

    ```shell
    aws eks update-kubeconfig --region <リージョン名> --name <クラスタ名>
    ```

- クラスタの確認

    ```shell
    kubectl cluster-info
    ```

<!-- - vCluster がインストールされていることを確認する

    ```shell
    ``` -->

