# -----------------------------------------------------------------------------
# cloudtrail-cwlogs — CloudWatch Logs integration for real-time analysis
#
# Logs reach S3 within ~5 minutes (archive/audit). CloudWatch Logs receives
# them in near-real-time so you can run metric filters + alarms on activity.
#
# This module creates:
#   - A CloudWatch Logs group (short retention — it's for active analysis)
#   - The IAM role CloudTrail ASSUMES to write to that group (the only role
#     in the whole design — S3 and KMS use resource-based policies instead)
#   - A metric filter + alarm example: alert on ROOT account usage, the
#     textbook "notify me immediately" CloudOps security event
#
# Exam note — two retentions on purpose:
#   S3 bucket keeps logs for the long audit horizon (e.g. 365 days).
#   CloudWatch Logs keeps a short window (e.g. 14 days) because it's the
#   hot, queryable copy, not the archive. Know that these are independent.
# -----------------------------------------------------------------------------

# --- Log group ---------------------------------------------------------------

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.prefix}"
  retention_in_days = var.retention_days

  tags = { Name = "${var.prefix}-cloudtrail-logs" }
}

# --- IAM role that CloudTrail assumes ----------------------------------------
# Trust policy: the CloudTrail service principal can assume this role.

resource "aws_iam_role" "cloudtrail_cwlogs" {
  name = "${var.prefix}-cloudtrail-cwlogs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-cloudtrail-cwlogs-role" }
}

# Permission policy: write streams + events to THIS log group only.
# CloudTrail creates a stream per account/region, so the resource is the
# log group's stream ARN (log group ARN + ":log-stream:*").

resource "aws_iam_role_policy" "cloudtrail_cwlogs" {
  name = "${var.prefix}-cloudtrail-cwlogs-policy"
  role = aws_iam_role.cloudtrail_cwlogs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:log-stream:*"
    }]
  })
}

# --- Metric filter + alarm: ROOT account usage -------------------------------
# Pattern matches any event where the caller identity is the account root user.
# Root should almost never be used day-to-day, so this is a classic alarm.

resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "${var.prefix}-root-usage"
  log_group_name = aws_cloudwatch_log_group.trail.name

  # Matches root sign-in / API usage that is NOT an AWS-service-invoked event.
  pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name          = "RootAccountUsage"
    namespace     = "CloudTrailMetrics"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${var.prefix}-root-account-usage"
  alarm_description   = "Fires when the AWS account root user performs any action"
  namespace           = "CloudTrailMetrics"
  metric_name         = "RootAccountUsage"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  # No SNS action in this lab — the alarm simply enters ALARM state, visible
  # in the console. Notifications (SNS) are added in a later alarms phase.
  alarm_actions = []

  tags = { Name = "${var.prefix}-root-account-usage" }
}
