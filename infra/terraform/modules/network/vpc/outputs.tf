output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC の CIDR"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "public サブネット ID（ALB・NAT Gateway 用）"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "private-app サブネット ID（ECS タスク・Interface エンドポイント用）"
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "private-db サブネット ID（Aurora・ElastiCache 用）"
  value       = aws_subnet.db[*].id
}

output "private_route_table_ids" {
  description = "private-app / private-db のルートテーブル ID（Gateway エンドポイントの関連付け用）"
  value       = concat(aws_route_table.app[*].id, [aws_route_table.db.id])
}
