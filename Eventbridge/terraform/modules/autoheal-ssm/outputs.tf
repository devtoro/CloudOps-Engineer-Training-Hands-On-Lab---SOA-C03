# -----------------------------------------------------------------------------
# autoheal-ssm module — outputs
# -----------------------------------------------------------------------------

output "rule_name" {
  description = "EventBridge rule that triggers the auto-heal"
  value       = aws_cloudwatch_event_rule.status_check_failed.name
}

output "ssm_document_name" {
  description = "SSM Automation document used to restart the instance"
  value       = local.ssm_document_name
}

output "automation_role_arn" {
  description = "ARN of the role the SSM Automation assumes (reused by the alarm module)"
  value       = aws_iam_role.automation.arn
}

output "events_invoke_role_arn" {
  description = "ARN of the role EventBridge uses to start the automation (reused by the alarm module)"
  value       = aws_iam_role.events_invoke.arn
}

output "ssm_document_arn" {
  description = "ARN of the SSM Automation document (reused by the alarm module)"
  value       = local.ssm_document_arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue for failed target deliveries"
  value       = aws_sqs_queue.dlq.url
}
