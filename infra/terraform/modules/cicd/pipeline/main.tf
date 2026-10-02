data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
  name       = "${var.name_prefix}-${var.service_name}"

  cluster_name = element(split("/", var.ecs_cluster_arn), 1)
  service_arn  = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${local.cluster_name}/${var.ecs_service_name}"

  # CodeBuild の各ステージ（Build / Migrate / Deploy）。buildspec はアプリリポジトリに置く
  stages = {
    build   = { buildspec = "buildspec.yml", privileged = true, timeout = 60 }
    migrate = { buildspec = "buildspec-migrate.yml", privileged = false, timeout = 60 }
    deploy  = { buildspec = "buildspec-deploy.yml", privileged = false, timeout = 120 }
  }

  common_env = {
    ENVIRONMENT         = var.environment
    AWS_ACCOUNT_ID      = local.account_id
    ECR_REPOSITORY_URI  = var.ecr_repository_url
    ECS_CLUSTER         = local.cluster_name
    ECS_SERVICE         = var.ecs_service_name
    TASK_FAMILY         = var.task_family
    CONTAINER_NAME      = var.container_name
    CONTAINER_PORT      = tostring(var.container_port)
    EXECUTION_ROLE_ARN  = var.execution_role_arn
    TASK_ROLE_ARN       = var.task_role_arn
    APP_LOG_GROUP       = var.app_log_group_name
    TASK_SUBNETS        = join(",", var.task_subnet_ids)
    TASK_SECURITY_GROUP = var.task_security_group_id
  }
}

# ---------------------------------------------------------------------------
# ソースリポジトリ（環境ごとのミラー。昇格は検証済みコミットを push して行う）
# ---------------------------------------------------------------------------
resource "aws_codecommit_repository" "this" {
  repository_name = local.name
  description     = "${local.name} application source (${var.environment})"
  default_branch  = var.source_branch
  kms_key_id      = var.kms_key_arn
}

# ---------------------------------------------------------------------------
# アーティファクトバケット
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name}-pipeline-${local.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = var.artifact_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# ---------------------------------------------------------------------------
# CodeBuild 共通（ログ・SG）
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name}"
  retention_in_days = var.build_log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_security_group" "codebuild" {
  name        = "${local.name}-codebuild"
  description = "CodeBuild for ${local.name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-codebuild" }
}

resource "aws_vpc_security_group_egress_rule" "codebuild_https" {
  security_group_id = aws_security_group.codebuild.id
  description       = "HTTPS (AWS APIs, base images)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# 全ステージ共通: ログ・アーティファクト・KMS・VPC 内実行
data "aws_iam_policy_document" "codebuild_common" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
  }

  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid = "VpcDescribe"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "VpcNetworkInterfacePermission"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "ec2:Subnet"
      values   = [for id in var.codebuild_subnet_ids : "arn:${local.partition}:ec2:${local.region}:${local.account_id}:subnet/${id}"]
    }
  }
}

# Build: イメージ push・スキャン結果確認・タスク定義登録
data "aws_iam_policy_document" "codebuild_build" {
  source_policy_documents = [data.aws_iam_policy_document.codebuild_common.json]

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arn]
  }

  # RegisterTaskDefinition はリソース指定に対応していない
  statement {
    sid       = "RegisterTaskDefinition"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.execution_role_arn, var.task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Migrate: マイグレーション用タスクの起動と結果確認
data "aws_iam_policy_document" "codebuild_migrate" {
  source_policy_documents = [data.aws_iam_policy_document.codebuild_common.json]

  statement {
    sid       = "RunTask"
    actions   = ["ecs:RunTask"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${var.task_family}:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  statement {
    sid       = "DescribeTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${local.cluster_name}/*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.execution_role_arn, var.task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Deploy: サービス更新と Blue/Green デプロイの監視
data "aws_iam_policy_document" "codebuild_deploy" {
  source_policy_documents = [data.aws_iam_policy_document.codebuild_common.json]

  statement {
    sid       = "UpdateService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:ListServiceDeployments"]
    resources = [local.service_arn]
  }

  statement {
    sid       = "DescribeServiceDeployments"
    actions   = ["ecs:DescribeServiceDeployments"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:service-deployment/${local.cluster_name}/${var.ecs_service_name}/*"]
  }
}

locals {
  codebuild_policies = {
    build   = data.aws_iam_policy_document.codebuild_build.json
    migrate = data.aws_iam_policy_document.codebuild_migrate.json
    deploy  = data.aws_iam_policy_document.codebuild_deploy.json
  }
}

resource "aws_iam_role" "codebuild" {
  for_each = local.stages

  name               = "${local.name}-codebuild-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

resource "aws_iam_role_policy" "codebuild" {
  for_each = local.stages

  name   = "codebuild-${each.key}"
  role   = aws_iam_role.codebuild[each.key].id
  policy = local.codebuild_policies[each.key]
}

resource "aws_codebuild_project" "this" {
  for_each = local.stages

  name           = "${local.name}-${each.key}"
  service_role   = aws_iam_role.codebuild[each.key].arn
  encryption_key = var.kms_key_arn
  build_timeout  = each.value.timeout

  source {
    type      = "CODEPIPELINE"
    buildspec = each.value.buildspec
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = each.value.privileged

    dynamic "environment_variable" {
      for_each = local.common_env
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.codebuild_subnet_ids
    security_group_ids = [aws_security_group.codebuild.id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = each.key
    }
  }

  depends_on = [aws_iam_role_policy.codebuild]
}

# ---------------------------------------------------------------------------
# CodePipeline
# Source → Build → (Approval: prod のみ) → Migrate → Deploy
# 承認より前に DB マイグレーションが走らないよう、Approval は Migrate の前に置く
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${local.name}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid = "Source"
    actions = [
      "codecommit:GetBranch",
      "codecommit:GetCommit",
      "codecommit:GetRepository",
      "codecommit:GetUploadArchiveStatus",
      "codecommit:UploadArchive",
      "codecommit:CancelUploadArchive",
    ]
    resources = [aws_codecommit_repository.this.arn]
  }

  statement {
    sid       = "Build"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [for p in aws_codebuild_project.this : p.arn]
  }

  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "codepipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

resource "aws_codepipeline" "this" {
  name          = local.name
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2"

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.id

    encryption_key {
      type = "KMS"
      id   = var.kms_key_arn
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.this.repository_name
        BranchName           = var.source_branch
        PollForSourceChanges = "false"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAndRegister"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.this["build"].name
      }
    }
  }

  dynamic "stage" {
    for_each = var.require_manual_approval ? [1] : []

    content {
      name = "Approval"

      action {
        name     = "ProductionApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          CustomData = "本番デプロイの承認。変更作成者以外が、変更内容・テスト結果・ステージング環境での確認結果を確認してから承認すること。"
        }
      }
    }
  }

  stage {
    name = "Migrate"

    action {
      name            = "DatabaseMigration"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput", "BuildOutput"]

      configuration = {
        ProjectName   = aws_codebuild_project.this["migrate"].name
        PrimarySource = "SourceOutput"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "BlueGreenDeploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput", "BuildOutput"]

      configuration = {
        ProjectName   = aws_codebuild_project.this["deploy"].name
        PrimarySource = "SourceOutput"
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]
}

# ---------------------------------------------------------------------------
# トリガー（対象ブランチへの push で起動）
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "source_push" {
  name        = "${local.name}-source-push"
  description = "Start ${local.name} pipeline on push to ${var.source_branch}"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [aws_codecommit_repository.this.arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [var.source_branch]
    }
  })
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = "${local.name}-pipeline-trigger"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "events" {
  statement {
    actions   = ["codepipeline:StartPipelineExecution"]
    resources = [aws_codepipeline.this.arn]
  }
}

resource "aws_iam_role_policy" "events" {
  name   = "start-pipeline"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events.json
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule     = aws_cloudwatch_event_rule.source_push.name
  arn      = aws_codepipeline.this.arn
  role_arn = aws_iam_role.events.arn
}

# ---------------------------------------------------------------------------
# 本番承認者用ポリシー（IAM Identity Center の承認者用権限セットに付与する）
# パイプライン・CodeBuild のロールには承認権限を与えない（職務分離）
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "approver" {
  statement {
    sid       = "ViewPipeline"
    actions   = ["codepipeline:GetPipeline", "codepipeline:GetPipelineState", "codepipeline:GetPipelineExecution", "codepipeline:ListPipelineExecutions"]
    resources = [aws_codepipeline.this.arn]
  }

  statement {
    sid       = "Approve"
    actions   = ["codepipeline:PutApprovalResult"]
    resources = ["${aws_codepipeline.this.arn}/Approval/ProductionApproval"]
  }
}
