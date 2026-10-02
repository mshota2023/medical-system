# Application Auto Scaling のスケジュールアクション（サービスリンクロールで動くため IAM ロールは不要）
# 同一ターゲットへの同時更新は競合するため、start は stop の後に作成する

# 停止: min/max を 0 にしてタスクを止める
resource "aws_appautoscaling_scheduled_action" "stop" {
  name               = "${var.name_prefix}-${var.service_name}-stop"
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = var.resource_id
  schedule           = var.stop_schedule
  timezone           = var.timezone

  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}

# 起動: 通常時の min/max に戻す（オートスケーリング有効時はこの範囲で再開する）
resource "aws_appautoscaling_scheduled_action" "start" {
  name               = "${var.name_prefix}-${var.service_name}-start"
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = var.resource_id
  schedule           = var.start_schedule
  timezone           = var.timezone

  scalable_target_action {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  depends_on = [aws_appautoscaling_scheduled_action.stop]
}
