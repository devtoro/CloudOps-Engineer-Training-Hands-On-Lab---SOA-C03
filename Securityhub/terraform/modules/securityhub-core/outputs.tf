# -----------------------------------------------------------------------------
# securityhub-core module — outputs
# -----------------------------------------------------------------------------

output "hub_arn" {
  description = "ARN of the enabled Security Hub account resource"
  value       = aws_securityhub_account.this.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector id (null if GuardDuty disabled)"
  value       = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}
