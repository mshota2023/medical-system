variable "repository_name" {
  description = "ECR リポジトリ名"
  type        = string
}

variable "kms_key_arn" {
  description = "イメージ暗号化に使う KMS キーの ARN（security/kms の data_key_arn）"
  type        = string
}

variable "max_image_count" {
  description = "保持するイメージ数の上限（ロールバック候補として残す世代数）"
  type        = number
  default     = 30
}

variable "replication_enabled" {
  description = "DR リージョン（aws.dr プロバイダーのリージョン）へイメージを複製するか"
  type        = bool
  default     = false
}

variable "replica_kms_key_arn" {
  description = "複製先リポジトリの暗号化に使う DR リージョンの KMS キー ARN（replication_enabled = true の場合は必須）"
  type        = string
  default     = null

  validation {
    condition     = !var.replication_enabled || var.replica_kms_key_arn != null
    error_message = "replication_enabled = true の場合は replica_kms_key_arn を指定してください。"
  }
}
