# EKS クラスタの構築

- Terraform 初期化を行う

    ```shell
    cd terraform
    terraform init -reconfigure
    ```

- 構築を開始

    ```shell
    terraform apply -var-file="terraform.tfvars"
    ```

- クレデンシャルを取得

    ```shell
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    ```

- クラスタの確認

    ```shell
    kubectl cluster-info
    ```
