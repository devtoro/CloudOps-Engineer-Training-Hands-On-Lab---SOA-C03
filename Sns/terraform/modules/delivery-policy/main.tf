# -----------------------------------------------------------------------------
# delivery-policy — HTTP/S subscription retry/backoff + DLQ monitoring
#
# RETRY & BACKOFF: SNS lets you tune delivery retries ONLY for HTTP/S endpoints,
# via a DELIVERY POLICY (healthyRetryPolicy). You set the number of retries, the
# backoff function (linear | geometric | exponential), min/max delay, and
# throttling. AWS-managed endpoints (SQS, Lambda, email) use fixed retry
# behavior you don't tune this way.
#
# This module:
#   - an HTTPS subscription (placeholder URL) with a custom retry/backoff policy
#   - a CloudWatch alarm on the DLQ's depth (monitor/troubleshoot failed delivery)
#
# Exam notes:
#   - Custom retry/backoff = HTTP/S only; backoff functions
#     linear/geometric/exponential; numRetries across immediate/pre/post/backoff
#     phases.
#   - "Messages piling in the DLQ" → alarm on ApproximateNumberOfMessagesVisible
#     of the DLQ; also watch SNS NumberOfNotificationsFailed /
#     NumberOfNotificationsFailedToRedriveToDlq.
#   - raw_message_delivery=false (default) wraps the payload in SNS JSON; true
#     passes the raw body (affects SQS/HTTP consumers + body-based filtering).
# -----------------------------------------------------------------------------

# =============================================================================
# HTTPS subscription with a custom retry/backoff delivery policy
# =============================================================================
resource "aws_sns_topic_subscription" "https" {
  topic_arn = var.standard_topic_arn
  protocol  = "https"
  endpoint  = var.https_endpoint

  # Don't let a bad placeholder endpoint block terraform apply.
  endpoint_auto_confirms = false

  # Per-subscription delivery (retry/backoff) policy for HTTP/S.
  delivery_policy = jsonencode({
    healthyRetryPolicy = {
      numRetries         = 5
      minDelayTarget     = 5   # seconds before first retry
      maxDelayTarget     = 60  # cap between retries
      numMinDelayRetries = 1
      numMaxDelayRetries = 2
      numNoDelayRetries  = 0
      backoffFunction    = "exponential" # linear | geometric | exponential
    }
    throttlePolicy = {
      maxReceivesPerSecond = 10
    }
  })
}

# =============================================================================
# CloudWatch alarm — DLQ depth (failed deliveries accumulating)
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.prefix}-sns-dlq-not-empty"
  alarm_description   = "Failed SNS deliveries are accumulating in the DLQ"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # No action wired in this lab — alarm visibly enters ALARM when the DLQ fills.
  # In practice you'd point alarm_actions at an SNS topic / EventBridge for
  # escalation or automated remediation.
  alarm_actions = []

  tags = { Name = "${var.prefix}-sns-dlq-not-empty" }
}
