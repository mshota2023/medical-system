output "cluster_name" {
  description = "ECS クラスター名"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS クラスター ARN"
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "ECS サービス名"
  value       = aws_ecs_service.this.name
}

output "task_family" {
  description = "タスク定義ファミリー名（CI はこのファミリーで新リビジョンを登録する）"
  value       = aws_ecs_task_definition.placeholder.family
}

output "container_name" {
  description = "コンテナ名"
  value       = var.container_name
}

output "execution_role_arn" {
  description = "タスク実行ロール ARN"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "タスクロール ARN"
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "アプリログのロググループ名"
  value       = aws_cloudwatch_log_group.app.name
}

output "task_security_group_id" {
  description = "タスクの SG ID（マイグレーション用 run-task でも使用）"
  value       = aws_security_group.task.id
}

output "autoscaling_resource_id" {
  description = "Application Auto Scaling のリソース ID（夜間停止のスケジュールアクションで使用）"
  value       = aws_appautoscaling_target.this.resource_id
}

output "min_capacity" {
  description = "通常時の最小タスク数"
  value       = aws_appautoscaling_target.this.min_capacity
}

output "max_capacity" {
  description = "通常時の最大タスク数"
  value       = aws_appautoscaling_target.this.max_capacity
}
