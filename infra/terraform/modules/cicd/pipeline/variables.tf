variable "name_prefix" {
  description = "リソース名の接頭辞（例: pacs-dev）"
  type        = string
}

variable "environment" {
  description = "環境名（CodeBuild の環境変数 ENVIRONMENT として渡す）"
  type        = string
}

variable "service_name" {
  description = "デプロイ対象のサービス名（リポジトリ・パイプライン名に使用）"
  type        = string
}

variable "source_branch" {
  description = "パイプラインを起動するブランチ"
  type        = string
  default     = "main"
}

variable "require_manual_approval" {
  description = "Migrate / Deploy の前に手動承認ステージを入れるか（prod は true）"
  type        = bool
}

variable "kms_key_arn" {
  description = "ソース・アーティファクト・ビルドの暗号化に使う KMS キーの ARN"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "CodeBuild ログの暗号化に使う KMS キーの ARN"
  type        = string
}

variable "vpc_id" {
  description = "CodeBuild を実行する VPC の ID"
  type        = string
}

variable "codebuild_subnet_ids" {
  description = "CodeBuild を実行するサブネット ID（NAT 経由で外部に出られる private-app）"
  type        = list(string)
}

variable "codebuild_image" {
  description = "CodeBuild のビルドイメージ"
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
}

variable "ecr_repository_arn" {
  description = "push 先 ECR リポジトリの ARN"
  type        = string
}

variable "ecr_repository_url" {
  description = "push 先 ECR リポジトリの URL"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "デプロイ先 ECS クラスターの ARN"
  type        = string
}

variable "ecs_service_name" {
  description = "デプロイ先 ECS サービス名"
  type        = string
}

variable "task_family" {
  description = "タスク定義ファミリー名"
  type        = string
}

variable "container_name" {
  description = "ALB に紐付くコンテナ名"
  type        = string
}

variable "container_port" {
  description = "コンテナポート"
  type        = number
}

variable "execution_role_arn" {
  description = "タスク実行ロール ARN（CI が登録するタスク定義に設定）"
  type        = string
}

variable "task_role_arn" {
  description = "タスクロール ARN（CI が登録するタスク定義に設定）"
  type        = string
}

variable "app_log_group_name" {
  description = "アプリログのロググループ名"
  type        = string
}

variable "task_subnet_ids" {
  description = "マイグレーション用タスクを起動するサブネット ID"
  type        = list(string)
}

variable "task_security_group_id" {
  description = "マイグレーション用タスクに付与する SG ID"
  type        = string
}

variable "artifact_retention_days" {
  description = "パイプラインアーティファクトの保存日数"
  type        = number
  default     = 90
}

variable "build_log_retention_days" {
  description = "CodeBuild ログの保持日数（変更管理の証跡）"
  type        = number
  default     = 365
}
