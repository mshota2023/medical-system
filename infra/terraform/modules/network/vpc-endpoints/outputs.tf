output "s3_gateway_endpoint_id" {
  description = "S3 Gateway エンドポイント ID（バケットポリシーの aws:SourceVpce 条件で使用）"
  value       = aws_vpc_endpoint.gateway["s3"].id
}

output "interface_security_group_id" {
  description = "Interface エンドポイントに付与した SG の ID"
  value       = aws_security_group.interface.id
}
