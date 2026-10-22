# =============================================================================
# Root outputs — uncomment as modules are added.
# =============================================================================

output "securityhub_arn" {
  description = "ARN of the enabled Security Hub"
  value       = module.securityhub_core.hub_arn
}
#
output "findings_bucket" {
  description = "S3 bucket receiving exported findings"
  value       = module.findings_export.bucket_name
}
#
output "response_lambda" {
  description = "Incident-response Lambda name"
  value       = module.finding_response.lambda_name
}
