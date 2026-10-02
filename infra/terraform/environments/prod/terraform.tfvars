environment    = "prod"
aws_account_id = "000000000000" # TODO: prod アカウント ID に置き換える

# =============================================================================
# 環境スイッチ
# 【不可逆】の付いた設定は、一度 apply すると tfvars を戻しても元の状態に戻らない。変更前に影響を確認すること
# =============================================================================
network_ha_enabled         = true  # AZ 障害時も外向き通信を継続する
ecs_scheduled_stop_enabled = false # 24時間稼働
ecs_autoscaling_enabled    = true  # CPU 使用率に応じて app_desired_count〜app_max_count で増減
ecs_container_insights     = "enabled"
ecs_exec_enabled           = false # prod は true 不可（validation）

# 【不可逆】一度 true で apply したバケットは Object Lock を無効化できない。false に戻しても新規ログに既定の保持期間が
#   かからなくなるだけで、ロック済みのログは保持期限まで削除できない
s3_object_lock_enabled = true # 監査ログの改ざん防止。prod は false 不可（validation）

# 【不可逆】true で apply すると、大阪のレプリカバケットに複製されたログは Object Lock の保持期限まで削除できない。
#   false に戻す場合は、先にレプリカバケットを terraform state rm で管理対象から外す（prevent_destroy のため。バケットとログは残る）
#   prod はレプリカにも COMPLIANCE ロックがかかるため、RTO/RPO 確定後に true にする（TODO）
dr_enabled = false

# =============================================================================
# ログ保持期間（日）
# =============================================================================
app_log_retention_days               = 365
build_log_retention_days             = 365
flow_logs_retention_days             = 365
cloudtrail_cloudwatch_retention_days = 90
alb_access_log_retention_days        = 365
pipeline_artifact_retention_days     = 90

# CloudTrail（S3）
# 【不可逆】書き込み済みのログには書き込み時点のモード・保持日数が適用され、後から変更しても反映されない。
#   COMPLIANCE で書き込んだログは保持期限まで root を含め誰も削除できず、期間短縮もできない
#   prod は COMPLIANCE のため、初回 apply 前に保持日数を必ず確定させること
# 保持期間は暫定で5年（法定保存期間・医療機関との契約との整合を要確認: docs/requirements.md）
cloudtrail_object_lock_mode        = "COMPLIANCE"
cloudtrail_object_lock_days        = 1827
cloudtrail_glacier_transition_days = 90
cloudtrail_log_retention_days      = 1827

# =============================================================================
# 個別設定
# =============================================================================
# network
vpc_cidr = "10.30.0.0/16"

# compute
acm_certificate_arn     = "arn:aws:acm:ap-northeast-1:000000000000:certificate/00000000-0000-0000-0000-000000000000" # TODO: prod の ACM 証明書に置き換える
alb_test_listener_cidrs = ["192.0.2.0/24"] # TODO: 運用者の接続元 CIDR に置き換える（0.0.0.0/0 不可）
alb_deletion_protection = true
app_desired_count       = 2  # 最小タスク数（オートスケーリング無効時は固定のタスク数）
app_max_count           = 4  # オートスケーリング時の最大タスク数
ecr_max_image_count     = 30 # ロールバック候補として残すイメージ世代数

# cicd
pipeline_require_manual_approval = true
