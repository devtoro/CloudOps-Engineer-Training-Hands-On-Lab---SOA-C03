# -----------------------------------------------------------------------------
# automation-eventbridge module — outputs
# -----------------------------------------------------------------------------

output "document_name" {
  description = "Name of the custom SSM Automation document"
  value       = aws_ssm_document.remediation.name
}

output "rule_name" {
  description = "EventBridge rule that triggers the automation"
  value       = aws_cloudwatch_event_rule.trigger.name
}
