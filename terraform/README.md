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
  echo "$REGION\n$CLUSTER_NAME"
  ```

- ARNを取得

  ```bash
  export DEV_KUBE_CONTEXT=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query "cluster.arn" --output text) &&\
  echo $DEV_KUBE_CONTEXT
  ```

- クレデンシャルを取得

  ```shell
  aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
  export EKSCONTEXT="$(kubectl config current-context)"
  echo $EKSCONTEXT
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
  helmfile destroy
  ```

- クラスタを破棄

  ```shell
  terraform destroy -var-file="terraform.tfvars"
  ```
