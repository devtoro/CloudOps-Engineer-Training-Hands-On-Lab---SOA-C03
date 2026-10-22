# -----------------------------------------------------------------------------
# autoheal-ssm — Auto-healing: unhealthy EC2 → SSM restarts it
#
# Flow:
#   EC2 Instance Status Check fails
#     → EventBridge rule matches the event (on the DEFAULT bus)
#     → target = SSM Automation document AWS-RestartEC2Instance
#     → EventBridge starts the automation using an "invoke" role
#     → the automation runs under its own AutomationAssumeRole and reboots
#     → failed deliveries go to a DLQ (SQS); retries are bounded
#
# TWO roles (classic exam distinction):
#   1. events_invoke role  → lets EVENTBRIDGE call ssm:StartAutomationExecution
#   2. automation role     → the AutomationAssumeRole the RUNBOOK runs as, which
#                            holds ec2:RebootInstances
#
# Monitoring/troubleshooting (your objective):
#   - DLQ captures events EventBridge could not deliver to the target.
#   - retry_policy bounds attempts/age.
#   - Rule metrics (Invocations, FailedInvocations) are in CloudWatch AWS/Events.
# -----------------------------------------------------------------------------

locals {
  ssm_document_name = "AWS-RestartEC2Instance"
  ssm_document_arn  = "arn:aws:ssm:${var.region}:${var.account_id}:automation-definition/${local.ssm_document_name}"
}

# =============================================================================
# Role 1 — the role the AUTOMATION assumes (AutomationAssumeRole)
# =============================================================================
resource "aws_iam_role" "automation" {
  name = "${var.prefix}-autoheal-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-autoheal-automation-role" }
}

# The runbook reboots the instance, so it needs ec2:RebootInstances.
resource "aws_iam_role_policy" "automation" {
  name = "${var.prefix}-autoheal-automation-policy"
  role = aws_iam_role.automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:RebootInstances", "ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
      Resource = "*"
    }]
  })
}

# =============================================================================
# Role 2 — the role EVENTBRIDGE uses to START the automation
# =============================================================================
resource "aws_iam_role" "events_invoke" {
  name = "${var.prefix}-autoheal-events-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-autoheal-events-role" }
}

# EventBridge needs to start the automation AND pass the automation role.
resource "aws_iam_role_policy" "events_invoke" {
  name = "${var.prefix}-autoheal-events-policy"
  role = aws_iam_role.events_invoke.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:StartAutomationExecution"]
        Resource = "${local.ssm_document_arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.automation.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" }
        }
      }
    ]
  })
}

# =============================================================================
# Dead-letter queue for undeliverable target invocations
# =============================================================================
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.prefix}-autoheal-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "${var.prefix}-autoheal-dlq" }
}

# Allow EventBridge to send failed events to the DLQ.
resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.status_check_failed.arn }
      }
    }]
  })
}

# =============================================================================
# The rule — match EC2 instance status-check failures (default bus)
# =============================================================================
resource "aws_cloudwatch_event_rule" "status_check_failed" {
  name        = "${var.prefix}-autoheal-state-change"
  description = "Restart the demo instance when it enters stopped (direct EC2 event)"

  # IMPORTANT (verified against AWS docs):
  #   EC2 emits "EC2 Instance State-change Notification" to the DEFAULT bus for
  #   lifecycle transitions (pending/running/stopping/stopped/terminated).
  #   There is NO native "status-check" EventBridge event — a failed STATUS
  #   CHECK is a CloudWatch METRIC (StatusCheckFailed_*), not an event. The
  #   metric-driven path is the alarm-to-eventbridge module (CP5), which is the
  #   correct way to react to status-check failures.
  #
  #   This rule therefore demonstrates the DIRECT-EVENT trigger using a real
  #   event: the instance entering "stopped". Stop the instance in the
  #   walkthrough and this rule fires → SSM restarts (reboots) it.
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    resources     = ["arn:aws:ec2:${var.region}:${var.account_id}:instance/${var.instance_id}"]
    detail = {
      state = ["stopped"]
    }
  })

  tags = { Name = "${var.prefix}-autoheal-state-change" }
}

# =============================================================================
# The target — the SSM Automation runbook
# =============================================================================
resource "aws_cloudwatch_event_target" "ssm_automation" {
  rule     = aws_cloudwatch_event_rule.status_check_failed.name
  arn      = local.ssm_document_arn
  role_arn = aws_iam_role.events_invoke.arn

  # Pass the instance id + the AutomationAssumeRole into the runbook parameters.
  input_transformer {
    input_paths = {
      instance = "$.detail.instance-id"
    }
    input_template = <<-EOT
      {
        "InstanceId": [<instance>],
        "AutomationAssumeRole": ["${aws_iam_role.automation.arn}"]
      }
    EOT
  }

  # Troubleshooting / resilience knobs.
  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }
}
