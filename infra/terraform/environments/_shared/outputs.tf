output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "app_subnet_ids" {
  description = "private-app サブネット ID"
  value       = module.vpc.app_subnet_ids
}

output "db_subnet_ids" {
  description = "private-db サブネット ID"
  value       = module.vpc.db_subnet_ids
}

output "data_kms_key_arn" {
  description = "医療情報用 KMS キーの ARN"
  value       = module.kms.data_key_arn
}

output "alb_dns_name" {
  description = "ALB の DNS 名"
  value       = module.alb.dns_name
}

output "codecommit_clone_url_grc" {
  description = "アプリリポジトリの clone URL（git-remote-codecommit 形式）"
  value       = module.pipeline.repository_clone_url_grc
}

output "pipeline_approver_policy_json" {
  description = "本番承認者用 IAM ポリシー（IAM Identity Center の承認者用権限セットに設定）"
  value       = module.pipeline.approver_policy_json
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail ログの出力先バケット名"
  value       = module.cloudtrail.bucket_name
}
