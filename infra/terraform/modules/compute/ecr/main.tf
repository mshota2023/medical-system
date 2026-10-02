data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_region" "dr" {
  provider = aws.dr
}

resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # 同一タグの上書きを禁止し、検証済みイメージのすり替えを防ぐ
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  dr_region  = data.aws_region.dr.region
  # 複製先リポジトリに作成テンプレートを当てる名前空間（例: pacs-dev/app → pacs-dev）
  template_prefix = split("/", var.repository_name)[0]

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the latest images (rollback candidates)"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# DR: DR リージョンへのイメージ複製
# 複製先のリポジトリは ECR が自動作成するため、作成テンプレートで KMS 暗号化・タグ不変を揃える
# 有効化以降に push されたイメージだけが複製される
# ---------------------------------------------------------------------------
# レジストリ単位の設定（1アカウントに1つ）。このリポジトリだけを対象にする
resource "aws_ecr_replication_configuration" "this" {
  count = var.replication_enabled ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = local.dr_region
        registry_id = local.account_id
      }

      repository_filter {
        filter      = var.repository_name
        filter_type = "PREFIX_MATCH"
      }
    }
  }

  depends_on = [aws_ecr_repository_creation_template.replica]
}

data "aws_iam_policy_document" "replica_template_assume" {
  count = var.replication_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# 作成テンプレートで KMS を使う場合に ECR が引き受けるロール
resource "aws_iam_role" "replica_template" {
  count = var.replication_enabled ? 1 : 0

  name               = "${local.template_prefix}-ecr-replica-template"
  assume_role_policy = data.aws_iam_policy_document.replica_template_assume[0].json
}

data "aws_iam_policy_document" "replica_template" {
  count = var.replication_enabled ? 1 : 0

  statement {
    actions   = ["ecr:CreateRepository", "ecr:ReplicateImage", "ecr:TagResource"]
    resources = ["arn:${local.partition}:ecr:${local.dr_region}:${local.account_id}:repository/${local.template_prefix}/*"]
  }

  statement {
    actions   = ["kms:CreateGrant", "kms:RetireGrant", "kms:DescribeKey"]
    resources = [var.replica_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "replica_template" {
  count = var.replication_enabled ? 1 : 0

  name   = "create-replica-repository"
  role   = aws_iam_role.replica_template[0].id
  policy = data.aws_iam_policy_document.replica_template[0].json
}

resource "aws_ecr_repository_creation_template" "replica" {
  provider = aws.dr
  count    = var.replication_enabled ? 1 : 0

  prefix               = local.template_prefix
  description          = "Replicated repositories from the primary region (DR)"
  applied_for          = ["REPLICATION"]
  image_tag_mutability = "IMMUTABLE"
  custom_role_arn      = aws_iam_role.replica_template[0].arn
  lifecycle_policy     = local.lifecycle_policy

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.replica_kms_key_arn
  }

  depends_on = [aws_iam_role_policy.replica_template]
}
