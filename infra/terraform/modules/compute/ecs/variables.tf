variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "service_name" {
  description = "ECS サービス名"
  type        = string
  default     = "app"
}

variable "container_name" {
  description = "ALB に紐付けるコンテナ名（アプリリポジトリの taskdef.json と一致させる）"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "コンテナポート"
  type        = number
}

variable "placeholder_image" {
  description = "初回作成時のプレースホルダイメージ。container_port で待ち受けるものを指定する（既定は 8080 で待ち受ける非 root 版 nginx）"
  type        = string
  default     = "public.ecr.aws/nginx/nginx-unprivileged:stable-alpine"
}

variable "desired_count" {
  description = "最小タスク数（オートスケーリング無効時は固定のタスク数）。マルチ AZ のため 2 以上を推奨"
  type        = number
  default     = 2
}

variable "autoscaling_enabled" {
  description = "CPU 使用率に応じたオートスケーリング（desired_count〜max_count の範囲）"
  type        = bool
  default     = false
}

variable "max_count" {
  description = "オートスケーリング時の最大タスク数"
  type        = number
  default     = 4

  validation {
    condition     = var.max_count >= var.desired_count
    error_message = "max_count は desired_count 以上を指定してください。"
  }
}

variable "autoscaling_cpu_target" {
  description = "オートスケーリングの CPU 使用率の目標値（%）"
  type        = number
  default     = 60

  validation {
    condition     = var.autoscaling_cpu_target >= 10 && var.autoscaling_cpu_target <= 90
    error_message = "autoscaling_cpu_target は 10〜90 の範囲で指定してください。"
  }
}

variable "container_insights" {
  description = "Container Insights（enabled / enhanced / disabled）"
  type        = string
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights は enabled / enhanced / disabled のいずれかを指定してください。"
  }
}

variable "exec_enabled" {
  description = "ECS Exec（コンテナへの対話ログイン）。障害調査用。セッションは KMS で暗号化し、操作内容を CloudWatch Logs に記録する"
  type        = bool
  default     = false
}

variable "bake_time_in_minutes" {
  description = "Blue/Green 切替後、旧バージョン（Blue）を残して監視する時間（分）。この間はすぐにロールバックできる"
  type        = number
  default     = 10
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "タスクを配置するサブネット ID（private-app）"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB の SG ID（タスクへの受信元）"
  type        = string
}

variable "blue_target_group_arn" {
  description = "Blue ターゲットグループ ARN"
  type        = string
}

variable "green_target_group_arn" {
  description = "Green ターゲットグループ ARN"
  type        = string
}

variable "production_listener_rule_arn" {
  description = "本番リスナールール ARN"
  type        = string
}

variable "test_listener_rule_arn" {
  description = "テストリスナールール ARN"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "アプリログの暗号化に使う KMS キーの ARN"
  type        = string
}

variable "log_retention_days" {
  description = "アプリログの保持日数"
  type        = number
  default     = 365
}
