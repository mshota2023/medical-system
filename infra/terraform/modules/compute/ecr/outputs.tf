output "repository_arn" {
  description = "ECR リポジトリの ARN"
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "ECR リポジトリの URL"
  value       = aws_ecr_repository.this.repository_url
}
