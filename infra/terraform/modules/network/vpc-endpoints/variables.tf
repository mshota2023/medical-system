variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "Interface エンドポイントへの HTTPS を許可する送信元 CIDR"
  type        = string
}

variable "subnet_ids" {
  description = "Interface エンドポイントを配置するサブネット ID（private-app）"
  type        = list(string)
}

variable "route_table_ids" {
  description = "Gateway エンドポイントを関連付けるルートテーブル ID"
  type        = list(string)
}

variable "interface_services" {
  description = "作成する Interface エンドポイントのサービス名（com.amazonaws.<region>. 以降）"
  type        = list(string)
  default = [
    "ssm",
    "ssmmessages",
    "ec2messages",
    "ecr.api",
    "ecr.dkr",
    "logs",
    "kms",
    "sts",
  ]
}
