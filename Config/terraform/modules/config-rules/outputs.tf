# -----------------------------------------------------------------------------
# config-rules module — outputs
# -----------------------------------------------------------------------------

output "sse_rule_name" {
  description = "Name of the S3 SSE managed rule (used by the remediation module)"
  value       = aws_config_config_rule.s3_sse.name
}

output "required_tags_rule_name" {
  description = "Name of the required-tags managed rule"
  value       = aws_config_config_rule.required_tags.name
}

output "custom_rule_name" {
  description = "Name of the custom S3 naming rule"
  value       = aws_config_config_rule.s3_naming.name
}

output "rule_names" {
  description = "All deployed Config rule names"
  value = [
    aws_config_config_rule.s3_sse.name,
    aws_config_config_rule.required_tags.name,
    aws_config_config_rule.s3_naming.name,
  ]
}
