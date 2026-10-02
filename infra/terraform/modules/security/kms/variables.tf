variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "deletion_window_in_days" {
  description = "キー削除の待機期間（日）。誤削除による医療情報の復号不能を防ぐため最大値を推奨"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days は 7〜30 の範囲で指定してください。"
  }
}
