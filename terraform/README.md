# EKS クラスタの構築 (Terraform)

AWS EKS クラスタ + VPC + EBS CSI Driver を Terraform で構築します．

## バージョン

| ツール | バージョン |
| --- | --- |
| Terraform | 1.15.5 |
| AWS provider | 5.x |
| EKS module | v20 系 |
| VPC module | v5 系 |
| EKS バージョン | 1.34 |
| ノードインスタンス | t3.large × 3 |

## 構築手順

```bash
cd terraform/

# tfvars を生成（IAM ARN を自動取得）
echo "eks_access_entry_principal_arn = $(aws sts get-caller-identity --output json --no-cli-pager | jq '.Arn')" > terraform.tfvars

# 初期化
terraform init
# 2 回目以降は terraform init -reconfigure

# 確認
terraform plan -var-file="terraform.tfvars"

# 適用（15〜20 分）
terraform apply -var-file="terraform.tfvars"
```

## kubeconfig の取得

```bash
export REGION="ap-northeast-1"
export CLUSTER_NAME="demo-eks-vcluster"

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
kubectl cluster-info
kubectl get nodes
```

## EBS CSI Driver の確認

```bash
kubectl get pods -n kube-system | grep ebs
```

## 破棄

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"
```
