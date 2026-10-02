data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
}

resource "aws_ecs_cluster" "this" {
  name = var.name_prefix

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  # ECS Exec のセッションを KMS で暗号化し、操作内容を監査ログとして残す
  dynamic "configuration" {
    for_each = var.exec_enabled ? [1] : []
    content {
      execute_command_configuration {
        kms_key_id = var.logs_kms_key_arn
        logging    = "OVERRIDE"

        log_configuration {
          cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec[0].name
          cloud_watch_encryption_enabled = true
        }
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name_prefix}/${var.service_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_cloudwatch_log_group" "exec" {
  count = var.exec_enabled ? 1 : 0

  name              = "/ecs/${var.name_prefix}/${var.service_name}/exec"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

# ---------------------------------------------------------------------------
# IAM ロール
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# タスク実行ロール（イメージ取得・ログ送信。ECS エージェントが使用）
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-${var.service_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# タスクロール（アプリケーションが使用）。権限は S3・Aurora 等の実装時に最小限で追加する
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-${var.service_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ECS Exec 用（SSM のセッションチャネル・監査ログの書き込み・セッション暗号化キー）
data "aws_iam_policy_document" "exec" {
  count = var.exec_enabled ? 1 : 0

  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.exec[0].arn}:*"]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.logs_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "exec" {
  count = var.exec_enabled ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.exec[0].json
}

# ECS が Blue/Green 切替時に ALB のリスナールールを操作するためのロール
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "load_balancer" {
  name               = "${var.name_prefix}-${var.service_name}-ecs-lb"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "load_balancer" {
  role       = aws_iam_role.load_balancer.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

# ---------------------------------------------------------------------------
# セキュリティグループ（ALB からのみ受信）
# ---------------------------------------------------------------------------
resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-${var.service_name}-task"
  description = "ECS tasks for ${var.service_name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-${var.service_name}-task" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.task.id
  description                  = "From ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = var.alb_security_group_id
}

# AWS API（VPC エンドポイント / NAT 経由）への HTTPS
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.task.id
  description       = "HTTPS to AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# タスク定義（初回作成用のプレースホルダ）
# 以降のリビジョンはアプリリポジトリの taskdef.json から CI が登録する
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "placeholder" {
  family                   = "${var.name_prefix}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name         = var.container_name
      image        = var.placeholder_image
      essential    = true
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = local.region
          awslogs-stream-prefix = var.container_name
        }
      }
    },
  ])

  # CI が新リビジョンを登録した後も、Terraform がプレースホルダで上書きしないようにする
  lifecycle {
    ignore_changes = all
  }
}

# ---------------------------------------------------------------------------
# サービス（ECS ネイティブ Blue/Green）
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name                   = var.service_name
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.placeholder.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  propagate_tags         = "SERVICE"
  enable_execute_command = var.exec_enabled

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.blue_target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port

    advanced_configuration {
      alternate_target_group_arn = var.green_target_group_arn
      production_listener_rule   = var.production_listener_rule_arn
      test_listener_rule         = var.test_listener_rule_arn
      role_arn                   = aws_iam_role.load_balancer.arn
    }
  }

  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = var.bake_time_in_minutes
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # task_definition: CI がデプロイのたびに更新する
  # load_balancer   : Blue/Green 完了後に ECS が本番ターゲットグループを入れ替える
  # desired_count   : 作成後は Application Auto Scaling（下記）が管理する
  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count]
  }

  depends_on = [aws_iam_role_policy_attachment.load_balancer]
}

# ---------------------------------------------------------------------------
# タスク数の管理（Application Auto Scaling）
# オートスケーリング無効時も min = max = desired_count で登録し、夜間停止（ecs-scheduled-stop）と
# タスク数の管理方法を揃える
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  min_capacity       = var.desired_count
  max_capacity       = var.autoscaling_enabled ? var.max_count : var.desired_count
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.autoscaling_enabled ? 1 : 0

  name               = "${var.name_prefix}-${var.service_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
