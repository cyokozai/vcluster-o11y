# 1\. EKS クラスタの構築

- move `terraform` directory

  ```bash
  cd terraform
  ```

- IAM ユーザまたは IAM ロールの ARN を取得する

  ```shell
  aws sts get-caller-identity
  ```

- `terraform` ディレクトリへ移動し、 `terraform.tfvars` を作成し、先ほど取得した ARN を指定する

  ```hcl
  eks_access_entry_principal_arn = "arn:aws:iam::hogehoge"
  ```

- 初期化を行う

  ```shell
  terraform init

  # 2回目以降
  terraform init -reconfigure
  ```

- 構築を開始

  ```shell
  terraform apply -var-file="terraform.tfvars"
  ```

- リージョンとクラスタ名を変数に保存

  ```bash
  export REGION="ap-northeast-1" &&\
  export CLUSTER_NAME="demo-eks-vcluster" &&\
  echo "$REGION" &&\
  echo "$CLUSTER_NAME"
  ```

- クレデンシャルを取得

  ```shell
  aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
  export DEV_KUBE_CONTEXT="$(kubectl config current-context)"
  echo $DEV_KUBE_CONTEXT
  ```

- クラスタの確認

  ```shell
  kubectl cluster-info
  ```

- gp3 StorageClass をデプロイ

  ```bash
  cd ..
  kubectl apply -f manifests/storageclass/gp3-storageclass.yaml
  ```

---

- Helm で管理するリソースをアンインストール

  ```bash
  helmfile destroy --file ../helm/
  ```

- クラスタを破棄

  ```shell
  terraform destroy -var-file="terraform.tfvars"
  ```
