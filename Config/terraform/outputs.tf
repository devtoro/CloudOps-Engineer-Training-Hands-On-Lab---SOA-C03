# =============================================================================
# Root outputs — uncomment as modules are added at each checkpoint.
# =============================================================================

output "config_bucket_name" {
  description = "S3 bucket storing Config configuration snapshots + history"
  value       = module.config_recorder.bucket_name
}

output "config_recorder_name" {
  description = "Name of the configuration recorder"
  value       = module.config_recorder.recorder_name
}
#
output "config_rule_names" {
  description = "Names of the deployed Config rules"
  value       = module.config_rules.rule_names
}
