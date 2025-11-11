# EKS クラスタの構築

- IAM ユーザまたは IAM ロールの ARN を取得する

  ```shell
  aws sts get-caller-identity
  ```

- `terraform.tfvars` を作成し、先ほど取得した ARN を指定する

  ```hcl
  eks_access_entry_principal_arn = "arn:aws:iam::hogehoge"
  ```

- `terraform` ディレクトリへ移動し初期化を行う

  ```shell
  terraform init

  # 2回目以降
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

- クラスタを破棄

  ```shell
  terraform destroy -var-file="terraform.tfvars"
  ```
