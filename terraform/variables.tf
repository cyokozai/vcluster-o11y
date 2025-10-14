variable "aws_region" {
  default     = "ap-northeast-1"
  type        = string
  description = "AWS region"
}

variable "cluster_name" {
  default     = "demo-eks-vcluster"
  type        = string
  description = "EKS Cluster name"
}

variable "cluster_version" {
  default     = "1.34"
  type        = string
  description = "EKS Cluster version"
}

variable "ebs_csi_name" {
  default     = "aws-ebs-csi-driver"
  type        = string
  description = "EKS Addon name"
}

variable "ebs_csi_version" {
  default     = "v1.50.1-eksbuild.1"
  type        = string
  description = "EKS Addon version"
}

variable "common_tags" {
  type = map(string)
  default = {
    Owner   = "intern-inoue"
    Purpose = "eks-vcluster-test"
  }
  description = "Common tags"
}

variable "eks_access_entry_principal_arn" {
  type = string
  description = "EKS Access Entry principal ARN"
}
