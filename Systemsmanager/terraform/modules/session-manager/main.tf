# -----------------------------------------------------------------------------
# session-manager — Session Manager logging to S3 + CloudWatch Logs
#
# Session Manager connects you to a managed node with NO inbound ports, NO
# bastion, NO SSH keys — access is via IAM, the agent dials out over 443.
#
# Session logging is configured through a SPECIAL SSM document of type
# "Session" named exactly "SSM-SessionManagerRunShell". Its content declares the
# S3 bucket and/or CloudWatch log group that receive the session transcript.
# There is ONE such document per account/region (account-level preference).
#
# For logging to work, the MANAGED INSTANCE'S ROLE (not a separate role) needs
# permission to write to the S3 bucket + the CloudWatch log group — the agent
# ships the transcript using the instance's own credentials.
#
# CloudOps exam notes:
#   - Session logging = audit trail of WHO connected + WHAT they typed/ran,
#     delivered to S3 and/or CloudWatch Logs. API calls also land in CloudTrail.
#   - The config lives in the SSM-SessionManagerRunShell document.
#   - KMS encryption of session data is an additional option (shown commented).
# -----------------------------------------------------------------------------

# =============================================================================
# S3 bucket for session logs
# =============================================================================
resource "aws_s3_bucket" "sessions" {
  bucket        = "${var.prefix}-sessions-${var.account_id}"
  force_destroy = true
  tags          = { Name = "${var.prefix}-sessions" }
}

resource "aws_s3_bucket_public_access_block" "sessions" {
  bucket                  = aws_s3_bucket.sessions.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sessions" {
  bucket = aws_s3_bucket.sessions.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# CloudWatch log group for session logs
# =============================================================================
resource "aws_cloudwatch_log_group" "sessions" {
  name              = "/ssm/session-logs/${var.prefix}"
  retention_in_days = var.cwlogs_retention_days
  tags              = { Name = "${var.prefix}-sessions" }
}

# =============================================================================
# Permissions on the INSTANCE role to ship session logs
# =============================================================================
resource "aws_iam_role_policy" "session_logging" {
  name = "${var.prefix}-session-logging"
  role = var.instance_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3SessionLogs"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetEncryptionConfiguration"]
        Resource = ["${aws_s3_bucket.sessions.arn}/*", aws_s3_bucket.sessions.arn]
      },
      {
        Sid      = "CWLogsSessionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
        Resource = "${aws_cloudwatch_log_group.sessions.arn}:*"
      }
    ]
  })
}

# =============================================================================
# The account/region Session Manager preferences document
#
# Name MUST be "SSM-SessionManagerRunShell" and type "Session". Terraform owns
# this document, so the lab controls the logging prefs declaratively.
# =============================================================================
resource "aws_ssm_document" "session_prefs" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences - log to S3 + CloudWatch"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.sessions.id
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      runAsEnabled                = false
      # --- Optional KMS encryption of session data (commented) --------------
      # kmsKeyId = aws_kms_key.sessions.key_id
    }
  })

  tags = { Name = "${var.prefix}-session-prefs" }
}
