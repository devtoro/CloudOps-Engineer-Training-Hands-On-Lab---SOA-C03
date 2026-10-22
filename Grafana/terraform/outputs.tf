# =============================================================================
# Root outputs — uncomment as modules are added.
# =============================================================================

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace id"
  value       = module.prometheus_workspace.workspace_id
}

output "amp_remote_write_url" {
  description = "AMP remote-write endpoint (for Prometheus/containers)"
  value       = module.prometheus_workspace.remote_write_url
}
#
output "grafana_workspace_endpoint" {
  description = "AMG workspace URL"
  value       = module.grafana_workspace.endpoint
}
