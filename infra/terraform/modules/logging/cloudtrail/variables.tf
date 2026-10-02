variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "kms_key_arn" {
  description = "ログ暗号化に使う KMS キーの ARN（security/kms の logs_key_arn）"
  type        = string
}

variable "external_bucket_name" {
  description = "ログ集約アカウント等の既存バケットに出力する場合のバケット名。null の場合はこのモジュールでバケットを作成する"
  type        = string
  default     = null
}

variable "object_lock_enabled" {
  description = "Object Lock（改ざん防止）を有効にするか。一度有効にしたバケットは無効化できず、false にしても既定の保持期間が外れるだけ（ロック済みオブジェクトは保護されたまま）"
  type        = bool
  default     = true
}

variable "object_lock_mode" {
  description = "Object Lock のモード。COMPLIANCE は保持期間中、root を含め誰も削除できないため prod でのみ使用する"
  type        = string

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode は GOVERNANCE または COMPLIANCE を指定してください。"
  }
}

variable "object_lock_days" {
  description = "Object Lock の保持日数（改ざん防止期間）"
  type        = number

  validation {
    condition     = var.object_lock_days >= 1
    error_message = "object_lock_days は 1 以上を指定してください。"
  }
}

variable "log_retention_days" {
  description = "ログの保存日数。経過後に削除する。object_lock_days 以上であること"
  type        = number

  validation {
    condition     = var.log_retention_days >= var.object_lock_days
    error_message = "log_retention_days は object_lock_days 以上を指定してください。"
  }
}

variable "glacier_transition_days" {
  description = "Glacier へ移行するまでの日数。log_retention_days 以上の場合は移行しない"
  type        = number
  default     = 90
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch Logs 側の保持日数（調査・検知用）"
  type        = number
  default     = 90
}

variable "replication_enabled" {
  description = "DR リージョン（aws.dr プロバイダーのリージョン）のレプリカバケットへ複製するか。external_bucket_name 指定時は無視する"
  type        = bool
  default     = false
}

variable "replica_kms_key_arn" {
  description = "レプリカバケットの暗号化に使う DR リージョンの KMS キー ARN（replication_enabled = true の場合は必須）"
  type        = string
  default     = null

  validation {
    condition     = !var.replication_enabled || var.replica_kms_key_arn != null
    error_message = "replication_enabled = true の場合は replica_kms_key_arn を指定してください。"
  }
}
