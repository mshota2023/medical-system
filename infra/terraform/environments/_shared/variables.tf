variable "system_name" {
  description = "システム名（リソース名の接頭辞に使用）"
  type        = string
  default     = "pacs"
}

variable "environment" {
  description = "環境名"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment は dev / stg / prod のいずれかを指定してください。"
  }
}

variable "aws_account_id" {
  description = "この環境をデプロイする AWS アカウント ID（誤適用防止）"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id は12桁の数字で指定してください。"
  }
}

variable "region" {
  description = "デプロイ先リージョン。医療情報の越境移転を防ぐため国内リージョンに限定する"
  type        = string
  default     = "ap-northeast-1"

  validation {
    condition     = contains(["ap-northeast-1", "ap-northeast-3"], var.region)
    error_message = "region は国内リージョン（ap-northeast-1 / ap-northeast-3）を指定してください。"
  }
}

# ---------------------------------------------------------------------------
# 環境スイッチ（各環境の terraform.tfvars で切り替える）
# ---------------------------------------------------------------------------
variable "network_ha_enabled" {
  description = "ネットワークの冗長構成。true の場合 NAT Gateway・Interface エンドポイントを AZ ごとに置く（false は単一 AZ に集約してコストを抑える。AZ 障害時は外向き通信と AWS API 呼び出しが止まる）"
  type        = bool
  default     = true
}

variable "ecs_scheduled_stop_enabled" {
  description = "ECS タスクの夜間・休日（土日）停止。true の場合 ecs_stop_schedule でタスク数を 0 にし、ecs_start_schedule で通常時のタスク数（オートスケーリング有効時はその範囲）に戻す"
  type        = bool
  default     = false
}

variable "ecs_stop_schedule" {
  description = "ECS タスクを停止する時刻（EventBridge Scheduler の cron 式、Asia/Tokyo）"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "ecs_start_schedule" {
  description = "ECS タスクを起動する時刻（EventBridge Scheduler の cron 式、Asia/Tokyo）。平日のみ起動するため、金曜夜の停止から月曜朝まで止まる"
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
}

variable "ecs_autoscaling_enabled" {
  description = "ECS のオートスケーリング。true の場合 CPU 使用率に応じて app_desired_count〜app_max_count の範囲でタスク数を増減する"
  type        = bool
  default     = false
}

variable "ecs_container_insights" {
  description = "ECS の Container Insights（enabled / enhanced / disabled）。disabled にするとメトリクス費用を抑えられる"
  type        = string
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.ecs_container_insights)
    error_message = "ecs_container_insights は enabled / enhanced / disabled のいずれかを指定してください。"
  }
}

variable "ecs_exec_enabled" {
  description = "ECS Exec（コンテナへの対話ログイン）。障害調査用。操作内容は CloudWatch Logs に記録する。prod では有効化できない"
  type        = bool
  default     = false

  validation {
    condition     = !var.ecs_exec_enabled || var.environment != "prod"
    error_message = "prod では ecs_exec_enabled を true にできません（本番コンテナへの対話ログインを禁止するため）。"
  }
}

variable "s3_object_lock_enabled" {
  description = "ログバケット等の S3 Object Lock（改ざん防止）。prod では無効化できない。有効化後に false にしても、ロック済みオブジェクトの保護は解除されない"
  type        = bool
  default     = true

  validation {
    condition     = var.s3_object_lock_enabled || var.environment != "prod"
    error_message = "prod では s3_object_lock_enabled を false にできません（監査ログの改ざん防止が必須のため）。"
  }
}

variable "dr_enabled" {
  description = "DR リージョン（dr_region）への複製。CloudTrail ログの S3 クロスリージョンレプリケーションと ECR イメージの複製を行う"
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "DR リージョン。医療情報の越境移転を防ぐため国内リージョンに限定し、region とは別のリージョンを指定する"
  type        = string
  default     = "ap-northeast-3"

  validation {
    condition     = contains(["ap-northeast-1", "ap-northeast-3"], var.dr_region) && var.dr_region != var.region
    error_message = "dr_region は region と異なる国内リージョン（ap-northeast-1 / ap-northeast-3）を指定してください。"
  }
}

# ---------------------------------------------------------------------------
# network
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC の CIDR（/16）"
  type        = string
}

variable "availability_zones" {
  description = "使用する AZ"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

variable "flow_logs_retention_days" {
  description = "VPC Flow Logs の保持日数"
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days は CloudWatch Logs が受け付ける保持日数（1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653）から選んでください。"
  }
}

variable "vpc_interface_endpoint_services" {
  description = "作成する Interface エンドポイントのサービス名"
  type        = list(string)
  default     = ["ssm", "ssmmessages", "ec2messages", "ecr.api", "ecr.dkr", "logs", "kms", "sts"]
}

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
variable "cloudtrail_external_bucket_name" {
  description = "ログ集約アカウントのバケットに出力する場合のバケット名（null の場合は環境アカウント内に作成）"
  type        = string
  default     = null
}

variable "cloudtrail_object_lock_mode" {
  description = "CloudTrail バケットの Object Lock モード（dev/stg は GOVERNANCE、prod は COMPLIANCE）"
  type        = string
}

variable "cloudtrail_object_lock_days" {
  description = "CloudTrail ログの Object Lock 保持日数"
  type        = number
}

variable "cloudtrail_log_retention_days" {
  description = "CloudTrail ログの保存日数"
  type        = number
}

variable "cloudtrail_glacier_transition_days" {
  description = "CloudTrail ログを Glacier へ移行するまでの日数（cloudtrail_log_retention_days 以上の場合は移行しない）"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_glacier_transition_days >= 1
    error_message = "cloudtrail_glacier_transition_days は 1 以上を指定してください。"
  }
}

variable "cloudtrail_cloudwatch_retention_days" {
  description = "CloudTrail の CloudWatch Logs 側の保持日数"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudtrail_cloudwatch_retention_days)
    error_message = "cloudtrail_cloudwatch_retention_days は CloudWatch Logs が受け付ける保持日数（1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653）から選んでください。"
  }
}

# ---------------------------------------------------------------------------
# compute
# ---------------------------------------------------------------------------
variable "app_service_name" {
  description = "アプリケーション（ECS サービス）名"
  type        = string
  default     = "app"
}

variable "app_container_port" {
  description = "アプリのコンテナポート"
  type        = number
  default     = 8080
}

variable "app_health_check_path" {
  description = "ALB ヘルスチェックのパス"
  type        = string
  default     = "/"
}

variable "app_desired_count" {
  description = "ECS の最小タスク数（オートスケーリング無効時は固定のタスク数）"
  type        = number
  default     = 2

  validation {
    condition     = var.app_desired_count >= 1
    error_message = "app_desired_count は 1 以上を指定してください（停止は ecs_scheduled_stop_enabled で行う）。"
  }
}

variable "app_max_count" {
  description = "オートスケーリング時の最大タスク数"
  type        = number
  default     = 4

  validation {
    condition     = var.app_max_count >= var.app_desired_count
    error_message = "app_max_count は app_desired_count 以上を指定してください。"
  }
}

variable "ecs_autoscaling_cpu_target" {
  description = "オートスケーリングの CPU 使用率の目標値（%）"
  type        = number
  default     = 60

  validation {
    condition     = var.ecs_autoscaling_cpu_target >= 10 && var.ecs_autoscaling_cpu_target <= 90
    error_message = "ecs_autoscaling_cpu_target は 10〜90 の範囲で指定してください。"
  }
}

variable "ecr_max_image_count" {
  description = "ECR に保持するイメージ数の上限（ロールバック候補の世代数）"
  type        = number
  default     = 30

  validation {
    condition     = var.ecr_max_image_count >= 1
    error_message = "ecr_max_image_count は 1 以上を指定してください。"
  }
}

variable "app_log_retention_days" {
  description = "アプリログ（CloudWatch Logs）の保持日数"
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.app_log_retention_days)
    error_message = "app_log_retention_days は CloudWatch Logs が受け付ける保持日数（1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653）から選んでください。"
  }
}

variable "app_bake_time_in_minutes" {
  description = "Blue/Green 切替後に旧バージョンを残して監視する時間（分）"
  type        = number
  default     = 10
}

variable "acm_certificate_arn" {
  description = "ALB の HTTPS リスナーに使う ACM 証明書 ARN"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:ap-northeast-[13]:[0-9]{12}:certificate/.+$", var.acm_certificate_arn))
    error_message = "acm_certificate_arn は国内リージョンの ACM 証明書 ARN を指定してください。"
  }
}

variable "alb_ingress_cidrs" {
  description = "ALB（443/80）への接続を許可する CIDR"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_test_listener_cidrs" {
  description = "Blue/Green テストリスナーへの接続を許可する CIDR（運用者のみ）"
  type        = list(string)
}

variable "alb_access_log_retention_days" {
  description = "ALB アクセスログ（S3）の保存日数"
  type        = number
  default     = 365

  validation {
    condition     = var.alb_access_log_retention_days >= 1
    error_message = "alb_access_log_retention_days は 1 以上を指定してください。"
  }
}

variable "alb_deletion_protection" {
  description = "ALB の削除保護"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# cicd
# ---------------------------------------------------------------------------
variable "pipeline_source_branch" {
  description = "パイプラインを起動するブランチ"
  type        = string
  default     = "main"
}

variable "build_log_retention_days" {
  description = "CodeBuild ログ（CloudWatch Logs）の保持日数（変更管理の証跡）"
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.build_log_retention_days)
    error_message = "build_log_retention_days は CloudWatch Logs が受け付ける保持日数（1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653）から選んでください。"
  }
}

variable "pipeline_artifact_retention_days" {
  description = "パイプラインアーティファクト（S3）の保存日数"
  type        = number
  default     = 90

  validation {
    condition     = var.pipeline_artifact_retention_days >= 1
    error_message = "pipeline_artifact_retention_days は 1 以上を指定してください。"
  }
}

variable "pipeline_require_manual_approval" {
  description = "Migrate / Deploy 前の手動承認ステージ（prod は true）"
  type        = bool
}
