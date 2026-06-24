output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.go_api_server.repository_url
  description = "ECR repository URL for go-api-server (use this in manifests/pattern-*/deploy.yaml)"
}

output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID"
}
