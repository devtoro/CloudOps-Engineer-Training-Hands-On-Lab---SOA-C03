# -----------------------------------------------------------------------------
# grafana-workspace module — outputs
# -----------------------------------------------------------------------------

output "endpoint" {
  description = "AMG workspace URL"
  value       = aws_grafana_workspace.this.endpoint
}

output "workspace_id" {
  description = "AMG workspace id"
  value       = aws_grafana_workspace.this.id
}

output "role_arn" {
  description = "IAM role AMG assumes to read data sources"
  value       = aws_iam_role.grafana.arn
}
