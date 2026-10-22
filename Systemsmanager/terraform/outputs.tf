# =============================================================================
# Root outputs — uncomment as modules are added.
# =============================================================================

output "instance_id" {
  description = "The SSM-managed EC2 instance"
  value       = module.managed_instance.instance_id
}
#
output "session_log_bucket" {
  description = "S3 bucket for Session Manager logs"
  value       = module.session_manager.log_bucket
}
#
output "patch_baseline_id" {
  description = "Custom patch baseline id"
  value       = module.patch_manager.baseline_id
}
#
output "automation_document_name" {
  description = "Custom SSM Automation document name"
  value       = module.automation_eventbridge.document_name
}
