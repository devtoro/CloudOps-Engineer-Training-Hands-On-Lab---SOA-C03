# -----------------------------------------------------------------------------
# patch-manager module — outputs
# -----------------------------------------------------------------------------

output "baseline_id" {
  description = "Custom patch baseline id"
  value       = aws_ssm_patch_baseline.this.id
}

output "maintenance_window_id" {
  description = "Maintenance window id running the patch scan"
  value       = aws_ssm_maintenance_window.this.id
}
