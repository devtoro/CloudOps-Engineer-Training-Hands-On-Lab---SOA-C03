# -----------------------------------------------------------------------------
# subscriptions — SQS + Lambda subscribers with FILTER POLICIES + a DLQ
#
# FAN-OUT with FILTERING: one publish to the topic, but each subscription only
# receives messages whose MESSAGE ATTRIBUTES match its FILTER POLICY. Publishers
# attach attributes (e.g. category=orders); subscriptions filter on them.
#
# DEAD-LETTER QUEUE: a redrive_policy on a SUBSCRIPTION points undeliverable
# messages to an SQS DLQ. DLQ is PER-SUBSCRIPTION (not per-topic) — it captures
# messages SNS failed to deliver to THAT subscriber after retries.
#
# Exam notes:
#   - Filter policies match on MessageAttributes by default; payload-based
#     filtering (FilterPolicyScope=MessageBody) is also available.
#   - SQS subscribers need a QUEUE POLICY allowing sns.amazonaws.com SendMessage.
#   - DLQ redrive is set with the subscription's redrive_policy.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# =============================================================================
# Subscriber SQS queues + a shared DLQ
# =============================================================================
resource "aws_sqs_queue" "orders" {
  name = "${var.prefix}-orders"
  tags = { Name = "${var.prefix}-orders" }
}

resource "aws_sqs_queue" "alerts" {
  name = "${var.prefix}-alerts"
  tags = { Name = "${var.prefix}-alerts" }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.prefix}-sns-dlq"
  message_retention_seconds = 1209600 # 14 days
  tags                      = { Name = "${var.prefix}-sns-dlq" }
}

# Queue policies: allow the SNS topic to SendMessage to each subscriber queue.
resource "aws_sqs_queue_policy" "orders" {
  queue_url = aws_sqs_queue.orders.id
  policy    = data.aws_iam_policy_document.allow_sns_orders.json
}

resource "aws_sqs_queue_policy" "alerts" {
  queue_url = aws_sqs_queue.alerts.id
  policy    = data.aws_iam_policy_document.allow_sns_alerts.json
}

data "aws_iam_policy_document" "allow_sns_orders" {
  statement {
    effect    = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.orders.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.standard_topic_arn]
    }
  }
}

data "aws_iam_policy_document" "allow_sns_alerts" {
  statement {
    effect    = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.alerts.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.standard_topic_arn]
    }
  }
}

# DLQ policy: allow SNS to deliver failed messages here.
resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = var.standard_topic_arn }
      }
    }]
  })
}

# =============================================================================
# Subscriptions with FILTER POLICIES
#   orders queue → only category=orders
#   alerts queue → only category=alerts AND severity in [high, critical]
#                  + a DLQ redrive policy (captures failed deliveries)
# =============================================================================
resource "aws_sns_topic_subscription" "orders" {
  topic_arn = var.standard_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.orders.arn

  filter_policy = jsonencode({
    category = ["orders"]
  })

  depends_on = [aws_sqs_queue_policy.orders]
}

resource "aws_sns_topic_subscription" "alerts" {
  topic_arn = var.standard_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.alerts.arn

  filter_policy = jsonencode({
    category = ["alerts"]
    severity = ["high", "critical"]
  })

  # Per-subscription DLQ: undeliverable messages land here after retries.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
  })

  depends_on = [aws_sqs_queue_policy.alerts, aws_sqs_queue_policy.dlq]
}

# =============================================================================
# Lambda subscriber (visible processed target) with its own filter policy
# =============================================================================
data "archive_file" "subscriber" {
  type        = "zip"
  source_dir  = var.subscriber_source_dir
  output_path = "${path.module}/subscriber.zip"
}

resource "aws_iam_role" "subscriber" {
  name = "${var.prefix}-subscriber-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "subscriber_logs" {
  name = "${var.prefix}-subscriber-logs"
  role = aws_iam_role.subscriber.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_lambda_function" "subscriber" {
  function_name    = "${var.prefix}-subscriber"
  role             = aws_iam_role.subscriber.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.subscriber.output_path
  source_code_hash = data.archive_file.subscriber.output_base64sha256
  tags             = { Name = "${var.prefix}-subscriber" }
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscriber.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.standard_topic_arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = var.standard_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.subscriber.arn

  # Only messages flagged category=orders reach the Lambda.
  filter_policy = jsonencode({
    category = ["orders"]
  })

  depends_on = [aws_lambda_permission.sns]
}
