output "security_group_id" {
  description = "ALB の SG ID（ECS タスク SG の受信元に指定）"
  value       = aws_security_group.this.id
}

output "dns_name" {
  description = "ALB の DNS 名"
  value       = aws_lb.this.dns_name
}

output "blue_target_group_arn" {
  description = "Blue ターゲットグループ ARN（ECS サービスの初期ターゲット）"
  value       = aws_lb_target_group.this["blue"].arn
}

output "green_target_group_arn" {
  description = "Green ターゲットグループ ARN（Blue/Green の代替ターゲット）"
  value       = aws_lb_target_group.this["green"].arn
}

output "production_listener_rule_arn" {
  description = "本番リスナールール ARN"
  value       = aws_lb_listener_rule.production.arn
}

output "test_listener_rule_arn" {
  description = "テストリスナールール ARN"
  value       = aws_lb_listener_rule.test.arn
}
