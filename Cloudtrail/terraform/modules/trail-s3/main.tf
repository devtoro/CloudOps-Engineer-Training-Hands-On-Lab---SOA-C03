# -----------------------------------------------------------------------------
# trail-s3 — Where CloudTrail stores its log files
#
# Components:
#   - S3 bucket (globally-unique name via account_id suffix)
#   - Block ALL public access (CloudTrail buckets must never be public)
#   - Versioning (protects against accidental overwrite/delete)
#   - KMS key + alias for SSE-KMS, with a key policy granting CloudTrail
#   - Bucket policy with the two required CloudTrail statements
#   - Lifecycle rule to expire logs after log_retention_days (retention)
#
# CloudOps exam notes are inline below.
# -----------------------------------------------------------------------------

# --- The bucket --------------------------------------------------------------

resource "aws_s3_bucket" "trail" {
  bucket = "${var.prefix}-logs-${var.account_id}"

  # Lab convenience: allow `terraform destroy` to remove a non-empty bucket.
  # NEVER set this on a real audit-log bucket.
  force_destroy = true

  tags = { Name = "${var.prefix}-logs" }
}

# --- Block public access (all four switches ON) ------------------------------
# Exam note: an audit-log bucket exposed publicly is a critical finding.
# These four settings together guarantee no public ACL or policy can apply.

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Versioning --------------------------------------------------------------

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- KMS key for SSE-KMS -----------------------------------------------------
# Exam note: the KMS KEY POLICY (not an IAM policy) is what authorizes
# CloudTrail to use the key. If CloudTrail can't call GenerateDataKey*, the
# trail silently fails to deliver logs. This is the #1 "trail not logging" cause.

resource "aws_kms_key" "trail" {
  description             = "KMS key for ${var.prefix} CloudTrail logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. Account root retains full control of the key (standard best practice,
      #    prevents locking yourself out of the key).
      {
        Sid       = "EnableRootPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      # 2. Allow CloudTrail to encrypt log files with this key.
      {
        Sid       = "AllowCloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${var.account_id}:trail/*"
          }
        }
      },
      # 3. Allow CloudTrail to describe the key.
      {
        Sid       = "AllowCloudTrailDescribeKey"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
      },
      # 4. Allow principals in this account to DECRYPT logs for reading
      #    (e.g. when you download and inspect a log file).
      {
        Sid       = "AllowAccountDecrypt"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = ["kms:Decrypt", "kms:ReEncryptFrom"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = var.account_id
          }
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${var.account_id}:trail/*"
          }
        }
      }
    ]
  })

  tags = { Name = "${var.prefix}-trail-key" }
}

resource "aws_kms_alias" "trail" {
  name          = "alias/${var.prefix}-trail"
  target_key_id = aws_kms_key.trail.key_id
}

# --- Default encryption: SSE-KMS with our key --------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.trail.arn
    }
    bucket_key_enabled = true
  }
}

# --- Bucket policy — the two required CloudTrail statements -------------------
# Exam note: these two statements are the canonical CloudTrail bucket policy.
#   - s3:GetBucketAcl on the BUCKET  → CloudTrail checks it owns/can write
#   - s3:PutObject on AWSLogs/<acct>/* with bucket-owner-full-control ACL
# The SourceArn condition scopes the policy to THIS trail only.

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/${var.trail_name}"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/${var.trail_name}"
          }
        }
      }
    ]
  })
}

# --- Lifecycle — retention ---------------------------------------------------
# Expire logs after N days. Also clean up old noncurrent versions (versioning
# is on) and incomplete multipart uploads so the bucket doesn't grow unbounded.

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
