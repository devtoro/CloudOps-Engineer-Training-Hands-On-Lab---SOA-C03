# -----------------------------------------------------------------------------
# alarm-to-eventbridge — CloudWatch alarm → EventBridge → SSM auto-heal
#
# The exam-relevant mechanism:
#   A CloudWatch ALARM STATE CHANGE is itself an EVENT on the default bus
#   (source "aws.cloudwatch", detail-type "CloudWatch Alarm State Change").
#   You do NOT wire the alarm's "actions" to EventBridge. Instead an EventBridge
#   RULE matches the alarm's transition to ALARM and triggers remediation.
#
# Flow:
#   StatusCheckFailed metric breaches
#     → CloudWatch alarm goes to ALARM
#     → alarm state change is emitted as an event
#     → EventBridge rule matches (this alarm, state = ALARM)
#     → target = SSM AWS-RestartEC2Instance (roles reused from autoheal-ssm)
#
# This gives you TWO independent triggers for the same remediation:
#   - direct EC2 status event (autoheal-ssm module) — fast, twitchy
#   - alarm-driven (this module) — slower, debounced across evaluation periods
# which is a realistic defense-in-depth pattern.
# -----------------------------------------------------------------------------

# --- The CloudWatch alarm ----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.prefix}-instance-status-check"
  alarm_description   = "Instance status check failed for the demo target"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  # No alarm_actions here — the state change itself is the event EventBridge
  # reacts to. (You COULD also add an EC2 recover action, but we're
  # demonstrating the EventBridge path.)
}

# --- The rule matching the alarm's state change ------------------------------
resource "aws_cloudwatch_event_rule" "alarm_state_change" {
  name        = "${var.prefix}-alarm-to-autoheal"
  description = "Trigger auto-heal when the status-check alarm enters ALARM"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.status_check.alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })

  tags = { Name = "${var.prefix}-alarm-to-autoheal" }
}

# --- Target the SSM runbook (reusing the autoheal-ssm roles) -----------------
resource "aws_cloudwatch_event_target" "ssm_automation" {
  rule     = aws_cloudwatch_event_rule.alarm_state_change.name
  arn      = var.ssm_document_arn
  role_arn = var.events_invoke_role_arn

  # The alarm event does not carry the instance id in a convenient path, so we
  # pass the known instance id as a constant into the runbook parameters.
  input_transformer {
    input_paths = {
      alarm = "$.detail.alarmName"
    }
    input_template = <<-EOT
      {
        "InstanceId": ["${var.instance_id}"],
        "AutomationAssumeRole": ["${var.automation_role_arn}"]
      }
    EOT
  }
}
