output "logs_key_arn" {
  description = "ログ用 KMS キーの ARN"
  value       = aws_kms_key.logs.arn
}

output "data_key_arn" {
  description = "データ用 KMS キーの ARN"
  value       = aws_kms_key.data.arn
}
