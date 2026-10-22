# -----------------------------------------------------------------------------
# config-remediation module — outputs
# -----------------------------------------------------------------------------

output "remediation_role_arn" {
  description = "ARN of the IAM role SSM Automation assumes to remediate"
  value       = aws_iam_role.remediation.arn
}

output "ssm_document" {
  description = "SSM Automation document used for remediation"
  value       = local.ssm_document_name
}
