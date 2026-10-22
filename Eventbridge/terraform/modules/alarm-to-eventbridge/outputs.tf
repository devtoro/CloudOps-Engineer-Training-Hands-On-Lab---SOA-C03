# -----------------------------------------------------------------------------
# alarm-to-eventbridge module — outputs
# -----------------------------------------------------------------------------

output "alarm_name" {
  description = "CloudWatch alarm whose state change drives the auto-heal"
  value       = aws_cloudwatch_metric_alarm.status_check.alarm_name
}

output "rule_name" {
  description = "EventBridge rule matching the alarm state change"
  value       = aws_cloudwatch_event_rule.alarm_state_change.name
}
