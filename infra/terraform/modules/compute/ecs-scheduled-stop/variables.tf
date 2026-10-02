variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "service_name" {
  description = "ECS サービス名（スケジュールアクション名に使用）"
  type        = string
}

variable "resource_id" {
  description = "Application Auto Scaling のリソース ID（compute/ecs の autoscaling_resource_id）"
  type        = string
}

variable "min_capacity" {
  description = "起動時に戻す最小タスク数（compute/ecs の min_capacity）"
  type        = number

  validation {
    condition     = var.min_capacity >= 1
    error_message = "min_capacity は 1 以上を指定してください。"
  }
}

variable "max_capacity" {
  description = "起動時に戻す最大タスク数（compute/ecs の max_capacity）"
  type        = number
}

variable "stop_schedule" {
  description = "タスクを停止する時刻（cron 式）"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"

  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.stop_schedule))
    error_message = "stop_schedule は cron(...) 形式で指定してください。"
  }
}

variable "start_schedule" {
  description = "タスクを起動する時刻（cron 式）"
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"

  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.start_schedule))
    error_message = "start_schedule は cron(...) 形式で指定してください。"
  }
}

variable "timezone" {
  description = "cron 式のタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}
