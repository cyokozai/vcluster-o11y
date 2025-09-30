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
  default     = "1.32"
  type        = string
  description = "EKS Cluster version"
}

variable "vcluster_namespace" {

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

variable "vcluster_namespace" {
  type        = string
  default     = "vcluster-demo"
  description = "Namespace to install vcluster"
}

variable "vcluster_chart_version" {
  type        = string
  default     = null
  description = "Version of the vcluster Helm chart"
}

variable "vcluster_values_file" {
  type        = string
  default     = "manifests/vcluster/vcluster.yaml"
  description = "Path to vcluster values file"
}
