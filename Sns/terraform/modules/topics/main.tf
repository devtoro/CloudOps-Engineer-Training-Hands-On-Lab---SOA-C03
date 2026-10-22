# -----------------------------------------------------------------------------
# topics — standard + FIFO SNS topics, KMS encryption, access policy
#
# SNS = managed pub/sub. A TOPIC is the channel publishers send to and
# subscribers receive from (fan-out). Two flavors:
#   - STANDARD : best-effort ordering, at-least-once, highest throughput.
#   - FIFO     : strict ordering + exactly-once (dedup) within a message group;
#                name MUST end .fifo; subscribers must be FIFO SQS queues.
#
# Security covered here:
#   - KMS CMK encrypts messages at rest (SSE). The key policy must let the SNS
#     service use the key (GenerateDataKey*/Decrypt) or publishes fail.
#   - Topic ACCESS POLICY controls who can Publish/Subscribe, and DENIES
#     non-TLS (aws:SecureTransport=false) to enforce encryption in transit.
#
# Exam notes:
#   - FIFO topic → FIFO SQS subscribers only; needs MessageGroupId (+ dedup).
#   - KMS + SNS: a missing key-policy grant for sns.amazonaws.com is a classic
#     "publish fails / messages not delivered" cause.
# -----------------------------------------------------------------------------

# =============================================================================
# KMS CMK for SNS encryption
# =============================================================================
resource "aws_kms_key" "sns" {
  description             = "KMS key for ${var.prefix} SNS topics"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowSNSUseOfKey"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      },
      {
        # Let the AWS services that publish (CloudWatch, EventBridge, etc.) use
        # the key when they encrypt messages to the topic.
        Sid    = "AllowServicePublishersUseOfKey"
        Effect = "Allow"
        Principal = {
          Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
        }
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${var.prefix}-sns-key" }
}

resource "aws_kms_alias" "sns" {
  name          = "alias/${var.prefix}-sns"
  target_key_id = aws_kms_key.sns.key_id
}

# =============================================================================
# Standard topic
# =============================================================================
resource "aws_sns_topic" "standard" {
  name              = "${var.prefix}-events"
  kms_master_key_id = aws_kms_key.sns.id

  tags = { Name = "${var.prefix}-events" }
}

# =============================================================================
# FIFO topic (ordering + dedup)
# =============================================================================
resource "aws_sns_topic" "fifo" {
  name                        = "${var.prefix}-events.fifo"
  fifo_topic                  = true
  content_based_deduplication = true
  kms_master_key_id           = aws_kms_key.sns.id

  tags = { Name = "${var.prefix}-events-fifo" }
}

# =============================================================================
# Access policy on the standard topic
#   - allow this account to publish/subscribe/manage
#   - allow CloudWatch + EventBridge service principals to publish
#   - DENY any request not using TLS (encryption in transit)
# =============================================================================
resource "aws_sns_topic_policy" "standard" {
  arn = aws_sns_topic.standard.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountManage"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action = [
          "sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes",
          "sns:SetTopicAttributes", "sns:ListSubscriptionsByTopic",
        ]
        Resource = aws_sns_topic.standard.arn
      },
      {
        Sid       = "AllowServicePublish"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"] }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.standard.arn
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.standard.arn
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
