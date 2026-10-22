# -----------------------------------------------------------------------------
# findings-export — Export Security Hub findings to S3
#
# Security Hub has no native "dump to S3" button. The AWS-recommended pattern:
#
#   Security Hub finding
#     → EventBridge event "Security Hub Findings - Imported" (default bus)
#     → EventBridge rule
#     → Kinesis Data Firehose delivery stream
#     → S3 bucket (batched, optionally compressed/partitioned)
#
# Firehose is preferred over a Lambda because it BATCHES and buffers at scale
# (findings can be high-volume), handles retries/backpressure, and needs no code.
# A Lambda alternative is shown COMMENTED OUT at the bottom.
#
# CloudOps exam notes:
#   - The event source is "aws.securityhub", detail-type
#     "Security Hub Findings - Imported" (new/updated findings).
#   - Firehose needs an IAM role to write to S3; EventBridge needs a role to
#     put records into Firehose. Two roles, same pattern as other targets.
# -----------------------------------------------------------------------------

# =============================================================================
# S3 bucket for exported findings
# =============================================================================
resource "aws_s3_bucket" "findings" {
  bucket        = "${var.prefix}-findings-${var.account_id}"
  force_destroy = true
  tags          = { Name = "${var.prefix}-findings" }
}

resource "aws_s3_bucket_public_access_block" "findings" {
  bucket                  = aws_s3_bucket.findings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "findings" {
  bucket = aws_s3_bucket.findings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# Firehose → S3 (with its IAM role)
# =============================================================================
resource "aws_iam_role" "firehose" {
  name = "${var.prefix}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-firehose-role" }
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "${var.prefix}-firehose-s3"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
      ]
      Resource = [
        aws_s3_bucket.findings.arn,
        "${aws_s3_bucket.findings.arn}/*",
      ]
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "findings" {
  name        = "${var.prefix}-findings-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.findings.arn

    # Batch to S3 every 5 min or 5 MB, whichever first, and partition by date.
    buffering_interval = 300
    buffering_size     = 5
    compression_format = "GZIP"
    prefix             = "securityhub-findings/!{timestamp:yyyy/MM/dd}/"
    error_output_prefix = "errors/"
  }

  tags = { Name = "${var.prefix}-findings-stream" }
}

# =============================================================================
# EventBridge rule: imported findings → Firehose
# =============================================================================
resource "aws_cloudwatch_event_rule" "findings" {
  name        = "${var.prefix}-export-findings"
  description = "Capture imported Security Hub findings and export them"

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
  })

  tags = { Name = "${var.prefix}-export-findings" }
}

# Role EventBridge assumes to put records into Firehose.
resource "aws_iam_role" "events_to_firehose" {
  name = "${var.prefix}-events-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-events-firehose-role" }
}

resource "aws_iam_role_policy" "events_to_firehose" {
  name = "${var.prefix}-events-firehose"
  role = aws_iam_role.events_to_firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.findings.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "firehose" {
  rule     = aws_cloudwatch_event_rule.findings.name
  arn      = aws_kinesis_firehose_delivery_stream.findings.arn
  role_arn = aws_iam_role.events_to_firehose.arn
}

# =============================================================================
# ALTERNATIVE: EventBridge → Lambda → S3 (commented out)
#
# Simpler for low volume or when you want to transform/filter each finding
# before writing. Trades Firehose's batching/backpressure for custom code.
#
# resource "aws_lambda_function" "export" {
#   function_name = "${var.prefix}-export-findings"
#   runtime       = "python3.12"
#   handler       = "handler.handler"
#   role          = aws_iam_role.export_lambda.arn
#   # ... package a handler that writes event["detail"]["findings"] to S3 ...
#   environment { variables = { BUCKET = aws_s3_bucket.findings.id } }
# }
#
# resource "aws_cloudwatch_event_target" "lambda" {
#   rule = aws_cloudwatch_event_rule.findings.name
#   arn  = aws_lambda_function.export.arn
# }
#
# resource "aws_lambda_permission" "events" {
#   statement_id  = "AllowEventBridge"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.export.function_name
#   principal     = "events.amazonaws.com"
#   source_arn    = aws_cloudwatch_event_rule.findings.arn
# }
#
# (The Lambda would need s3:PutObject on the findings bucket + logs perms.)
# =============================================================================
