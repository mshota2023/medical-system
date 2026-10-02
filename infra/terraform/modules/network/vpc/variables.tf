variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の CIDR。サブネット割り当ての都合上 /16 で指定する"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr は /16 の CIDR で指定してください（例: 10.10.0.0/16）。"
  }
}

variable "availability_zones" {
  description = "使用する AZ（マルチ AZ 構成のため 2〜3 個）"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3
    error_message = "availability_zones は 2〜3 個指定してください。"
  }
}

variable "single_nat_gateway" {
  description = "true の場合 NAT Gateway を1台に集約する（コスト優先。AZ 障害時は外向き通信が止まるため prod では false）"
  type        = bool
  default     = false
}

variable "logs_kms_key_arn" {
  description = "Flow Logs のロググループ暗号化に使う KMS キーの ARN"
  type        = string
}

variable "flow_logs_retention_days" {
  description = "VPC Flow Logs の保持日数"
  type        = number
  default     = 365
}
