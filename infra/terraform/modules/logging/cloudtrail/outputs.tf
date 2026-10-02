output "trail_arn" {
  description = "CloudTrail 証跡の ARN"
  value       = aws_cloudtrail.this.arn
}

output "bucket_name" {
  description = "CloudTrail ログの出力先バケット名"
  value       = local.bucket_name
}

output "log_group_name" {
  description = "CloudTrail の CloudWatch Logs ロググループ名（メトリクスフィルタ・アラームで使用）"
  value       = aws_cloudwatch_log_group.this.name
}

output "replica_bucket_name" {
  description = "DR リージョンのレプリカバケット名（複製しない場合は null）"
  value       = local.create_replica ? aws_s3_bucket.replica[0].id : null
}
