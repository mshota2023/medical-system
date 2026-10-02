environment    = "stg"
aws_account_id = "000000000000" # TODO: stg アカウント ID に置き換える

# =============================================================================
# 環境スイッチ
# 【不可逆】の付いた設定は、一度 apply すると tfvars を戻しても元の状態に戻らない。変更前に影響を確認すること
# =============================================================================
network_ha_enabled         = true  # 本番同等の冗長構成で検証する
ecs_scheduled_stop_enabled = true  # 平日 21:00〜8:00・土日はタスク数 0（祝日は対象外）
ecs_autoscaling_enabled    = false # 固定のタスク数（app_desired_count）で動かす
ecs_container_insights     = "enabled"
ecs_exec_enabled           = false # 必要時のみ一時的に true

# 【不可逆】一度 true で apply したバケットは Object Lock を無効化できない。false に戻しても新規ログに既定の保持期間が
#   かからなくなるだけで、ロック済みのログは保持期限まで削除できない
s3_object_lock_enabled = true # 監査ログの改ざん防止

# 【不可逆】true で apply すると、大阪のレプリカバケットに複製されたログは Object Lock の保持期限まで削除できない。
#   false に戻す場合は、先にレプリカバケットを terraform state rm で管理対象から外す（prevent_destroy のため。バケットとログは残る）
dr_enabled = false # 大阪リージョンへの複製なし（DR 手順の検証時のみ true）

# =============================================================================
# ログ保持期間（日）
# =============================================================================
app_log_retention_days               = 365
build_log_retention_days             = 365
flow_logs_retention_days             = 365
cloudtrail_cloudwatch_retention_days = 90
alb_access_log_retention_days        = 365
pipeline_artifact_retention_days     = 90

# CloudTrail（S3）。GOVERNANCE: 特別権限があれば削除可能
# 【不可逆】書き込み済みのログには書き込み時点のモード・保持日数が適用され、後から変更しても反映されない。
#   COMPLIANCE で書き込んだログは保持期限まで root を含め誰も削除できず、期間短縮もできない
cloudtrail_object_lock_mode        = "GOVERNANCE"
cloudtrail_object_lock_days        = 90
cloudtrail_glacier_transition_days = 90
cloudtrail_log_retention_days      = 365

# =============================================================================
# 個別設定
# =============================================================================
# network
vpc_cidr = "10.20.0.0/16"

# compute
acm_certificate_arn     = "arn:aws:acm:ap-northeast-1:000000000000:certificate/00000000-0000-0000-0000-000000000000" # TODO: stg の ACM 証明書に置き換える
alb_test_listener_cidrs = ["192.0.2.0/24"] # TODO: 運用者の接続元 CIDR に置き換える（0.0.0.0/0 不可）
alb_deletion_protection = true
app_desired_count       = 2  # 最小タスク数（オートスケーリング無効時は固定のタスク数）
app_max_count           = 4  # オートスケーリング時の最大タスク数
ecr_max_image_count     = 30 # ロールバック候補として残すイメージ世代数

# cicd
pipeline_require_manual_approval = false
