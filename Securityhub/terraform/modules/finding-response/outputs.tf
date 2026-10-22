# -----------------------------------------------------------------------------
# finding-response module — outputs
# -----------------------------------------------------------------------------

output "lambda_name" {
  description = "Incident-response Lambda function name"
  value       = aws_lambda_function.response.function_name
}

output "rule_name" {
  description = "EventBridge rule matching HIGH/CRITICAL findings"
  value       = aws_cloudwatch_event_rule.response.name
}
