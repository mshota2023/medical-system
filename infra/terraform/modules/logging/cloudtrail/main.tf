data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_region" "dr" {
  provider = aws.dr
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.region
  partition     = data.aws_partition.current.partition
  trail_name    = "${var.name_prefix}-trail"
  trail_arn     = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
  create_bucket = var.external_bucket_name == null
  bucket_name   = local.create_bucket ? aws_s3_bucket.this[0].id : var.external_bucket_name

  create_object_lock = local.create_bucket && var.object_lock_enabled
  # 外部バケット（ログ集約アカウント）を使う場合の複製は、集約アカウント側の責務とする
  create_replica = local.create_bucket && var.replication_enabled
}

# ---------------------------------------------------------------------------
# ログ保管用 S3 バケット（Object Lock による改ざん防止）
# external_bucket_name を指定した場合（ログ集約アカウント利用時）は作成しない
# Object Lock はバケット作成時ではなく aws_s3_bucket_object_lock_configuration で有効化する
# （既存バケットにも後から有効化でき、切り替えでバケットが置き換わらない）
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  count = local.create_bucket ? 1 : 0

  bucket = "${var.name_prefix}-cloudtrail-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count  = local.create_object_lock ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  # 一度有効化すると無効化できない（このリソースを削除しても既定の保持期間が外れるだけ）
  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = var.glacier_transition_days < var.log_retention_days ? [1] : []
      content {
        days          = var.glacier_transition_days
        storage_class = "GLACIER"
      }
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "bucket" {
  count = local.create_bucket ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this[0].arn, "${aws_s3_bucket.this[0].arn}/*"]

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

  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.this[0].arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this[0].arn}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# CloudWatch Logs 連携（検知・調査用。長期保管は S3 側で行う）
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "cloudwatch_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role" "cloudwatch" {
  name               = "${var.name_prefix}-cloudtrail-to-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_assume.json
}

data "aws_iam_policy_document" "cloudwatch" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "write-cloudtrail-logs"
  role   = aws_iam_role.cloudwatch.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

# ---------------------------------------------------------------------------
# 証跡（全リージョン・グローバルサービスイベント・ログファイル検証）
# ---------------------------------------------------------------------------
resource "aws_cloudtrail" "this" {
  name                          = local.trail_name
  s3_bucket_name                = local.bucket_name
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.this.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudwatch.arn

  depends_on = [aws_s3_bucket_policy.this, aws_iam_role_policy.cloudwatch]
}

# ---------------------------------------------------------------------------
# DR: レプリカバケット（DR リージョン）へのクロスリージョンレプリケーション
# 有効化以降に書き込まれたログだけが複製される（既存ログは S3 Batch Replication で複製する）
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0

  bucket = "${var.name_prefix}-cloudtrail-replica-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# 複製元と同じ保持設定にする（複製されたオブジェクトには元の保持期限も引き継がれる）
resource "aws_s3_bucket_object_lock_configuration" "replica" {
  provider = aws.dr
  count    = local.create_replica && var.object_lock_enabled ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id

  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.replica]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.replica_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = var.glacier_transition_days < var.log_retention_days ? [1] : []
      content {
        days          = var.glacier_transition_days
        storage_class = "GLACIER"
      }
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.replica]
}

data "aws_iam_policy_document" "replica_bucket" {
  count = local.create_replica ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.replica[0].arn, "${aws_s3_bucket.replica[0].arn}/*"]

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

resource "aws_s3_bucket_policy" "replica" {
  provider = aws.dr
  count    = local.create_replica ? 1 : 0
  bucket   = aws_s3_bucket.replica[0].id
  policy   = data.aws_iam_policy_document.replica_bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.replica]
}

data "aws_iam_policy_document" "replication_assume" {
  count = local.create_replica ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "replication" {
  count = local.create_replica ? 1 : 0

  name               = "${var.name_prefix}-cloudtrail-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
}

data "aws_iam_policy_document" "replication" {
  count = local.create_replica ? 1 : 0

  statement {
    sid       = "ReadSourceConfig"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.this[0].arn]
  }

  # Retention / LegalHold は Object Lock の保持設定を複製先へ引き継ぐために必要
  statement {
    sid = "ReadSourceObjects"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
      "s3:GetObjectRetention",
      "s3:GetObjectLegalHold",
    ]
    resources = ["${aws_s3_bucket.this[0].arn}/*"]
  }

  statement {
    sid = "WriteReplica"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.replica[0].arn}/*"]
  }

  statement {
    sid       = "DecryptSource"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "EncryptReplica"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.replica_kms_key_arn]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.dr.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "replication" {
  count = local.create_replica ? 1 : 0

  name   = "replicate-cloudtrail-logs"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count  = local.create_replica ? 1 : 0
  bucket = aws_s3_bucket.this[0].id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "dr"
    status = "Enabled"

    filter {}

    # 削除マーカーは複製しない（複製元での削除を DR 側に波及させない）
    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.replica[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = var.replica_kms_key_arn
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.this,
    aws_s3_bucket_versioning.replica,
    aws_s3_bucket_object_lock_configuration.replica,
    aws_iam_role_policy.replication,
  ]
}
