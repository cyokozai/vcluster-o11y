terraform {
  required_version = "~> 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95.0, < 6.0.0"
    }
    
    # helm = {
    #   source  = "hashicorp/helm"
    #   version = "~> 2.7"
    # }

    # kubernetes = {
    #   source  = "hashicorp/kubernetes"
    #   version = "~> 2.16"
    # }
  }
}

provider "aws" {
  region = var.aws_region
}

# providers.tf

# provider "kubernetes" {
#   host                   = module.eks.cluster_endpoint
#   cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "aws"
#     args = [
#       "eks",
#       "get-token",
#       "--cluster-name",
#       module.eks.cluster_name
#     ]
#   }
# }

# provider "helm" {
#   kubernetes {
#     host                   = module.eks.cluster_endpoint
#     cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

#     exec {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "aws"
#       args = [
#         "eks",
#         "get-token",
#         "--cluster-name",
#         module.eks.cluster_name
#       ]
#     }
#   }
# }
