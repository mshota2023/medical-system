variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）。ALB・ターゲットグループ名の文字数制限のため短くする"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の CIDR（ALB からターゲットへの送信先）"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB を配置する public サブネット ID"
  type        = list(string)
}

variable "certificate_arn" {
  description = "HTTPS リスナーの ACM 証明書 ARN"
  type        = string
}

variable "ssl_policy" {
  description = "TLS ポリシー（TLS 1.2 以上）"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "ingress_cidrs" {
  description = "ALB（443/80）への接続を許可する CIDR。CloudFront 導入後は CloudFront のマネージドプレフィックスリストに置き換える"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "test_listener_port" {
  description = "Blue/Green テストリスナーのポート"
  type        = number
  default     = 8443
}

variable "test_listener_cidrs" {
  description = "テストリスナーへの接続を許可する CIDR（運用者のみ。インターネット全体に開放しない）"
  type        = list(string)

  validation {
    condition     = !contains(var.test_listener_cidrs, "0.0.0.0/0")
    error_message = "test_listener_cidrs に 0.0.0.0/0 は指定できません。"
  }
}

variable "target_port" {
  description = "ECS タスクのコンテナポート"
  type        = number
}

variable "health_check_path" {
  description = "ターゲットグループのヘルスチェックパス"
  type        = string
  default     = "/"
}

variable "deletion_protection" {
  description = "ALB の削除保護"
  type        = bool
  default     = true
}

variable "access_log_retention_days" {
  description = "ALB アクセスログの保存日数"
  type        = number
  default     = 365
}
