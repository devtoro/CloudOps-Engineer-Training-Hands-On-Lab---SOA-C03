# -----------------------------------------------------------------------------
# config-recorder — The engine of AWS Config
#
# Four pieces that MUST be created in the right order:
#   1. S3 bucket (+ policy)        → where snapshots + history land
#   2. IAM role for Config         → lets Config read your resources + write S3
#   3. configuration_recorder      → defines WHAT to record (resource scope)
#   4. delivery_channel            → defines WHERE/HOW OFTEN to deliver
#   5. recorder_status (running)   → actually TURNS IT ON
#
# CloudOps exam notes:
#   - A recorder that EXISTS but is not STARTED records nothing. The
#     aws_config_configuration_recorder_status resource is the on-switch.
#   - The delivery channel requires the S3 bucket POLICY to already allow
#     Config, or creation fails ("insufficient permissions on bucket").
#   - A "configuration item" (CI) is a point-in-time snapshot of a resource's
#     config, its relationships, and metadata. The recorder emits a new CI on
#     every change (and on the snapshot schedule).
# -----------------------------------------------------------------------------

# =============================================================================
# 1. S3 bucket for configuration snapshots + history
# =============================================================================

resource "aws_s3_bucket" "config" {
  bucket = "${var.prefix}-${var.account_id}"

  # Lab convenience — allow destroy of a non-empty bucket. Never in prod.
  force_destroy = true

  tags = { Name = "${var.prefix}-config" }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

# The canonical AWS Config bucket policy:
#   - GetBucketAcl on the bucket (Config checks it can write)
#   - PutObject under AWSLogs/<acct>/Config/* with bucket-owner-full-control
# Scoped to this account + this Config role via conditions.
resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = { "AWS:SourceAccount" = var.account_id }
        }
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = { "AWS:SourceAccount" = var.account_id }
        }
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${var.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = var.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# 2. IAM role AWS Config assumes
# =============================================================================

resource "aws_iam_role" "config" {
  name = "${var.prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-config-role" }
}

# AWS-managed policy granting Config read access to describe resources.
resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Inline policy allowing delivery to our S3 bucket.
resource "aws_iam_role_policy" "config_s3" {
  name = "${var.prefix}-config-s3-delivery"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${var.account_id}/Config/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl"]
        Resource = aws_s3_bucket.config.arn
      }
    ]
  })
}

# =============================================================================
# 3. Configuration recorder — WHAT to record
# =============================================================================

resource "aws_config_configuration_recorder" "this" {
  name     = "${var.prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = var.record_all_resource_types
    include_global_resource_types = var.record_all_resource_types
  }
}

# =============================================================================
# 4. Delivery channel — WHERE + HOW OFTEN
#    Requires the bucket policy to exist first.
# =============================================================================

resource "aws_config_delivery_channel" "this" {
  name           = "${var.prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config,
  ]
}

# =============================================================================
# 5. Recorder status — the ON switch
#    Must come after the delivery channel exists.
# =============================================================================

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
