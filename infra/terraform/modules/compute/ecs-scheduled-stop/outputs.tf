output "scheduled_action_arns" {
  description = "停止・起動スケジュールアクションの ARN"
  value = {
    stop  = aws_appautoscaling_scheduled_action.stop.arn
    start = aws_appautoscaling_scheduled_action.start.arn
  }
}
