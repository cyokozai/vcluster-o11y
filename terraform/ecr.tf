data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "go_api_server" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}
