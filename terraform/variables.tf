variable "aws_region" {
  default     = "ap-northeast-1"
  description = "AWS region"
}

variable "cluster_name" {
  default     = "demo-eks-vcluster"
  description = "EKS Cluster name"
}

variable "common_tags" {
  type = map(string)
  default = {
    Owner   = "intern-inoue"
    Purpose = "eks-vcluster-test"
  }
}
