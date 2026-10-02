data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
}

# ---------------------------------------------------------------------------
# Gateway エンドポイント（無料。S3 / DynamoDB への通信を VPC 内に閉じる）
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(["s3", "dynamodb"])

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

# ---------------------------------------------------------------------------
# Interface エンドポイント（ECS のイメージ取得・ログ送信、SSM Session Manager 等）
# ---------------------------------------------------------------------------
resource "aws_security_group" "interface" {
  name        = "${var.name_prefix}-vpc-endpoints"
  description = "HTTPS from VPC to interface endpoints"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-vpc-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "interface_https" {
  security_group_id = aws_security_group.interface.id
  description       = "HTTPS from VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.interface.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-${each.key}" }
}
