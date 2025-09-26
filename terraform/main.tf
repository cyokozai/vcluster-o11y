terraform {
  required_version = "~> 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95.0, < 6.0.0"
    }
    
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  }
}
