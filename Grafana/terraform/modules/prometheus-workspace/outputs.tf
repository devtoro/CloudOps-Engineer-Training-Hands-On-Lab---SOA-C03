# -----------------------------------------------------------------------------
# prometheus-workspace module — outputs
# -----------------------------------------------------------------------------

output "workspace_id" {
  description = "AMP workspace id"
  value       = aws_prometheus_workspace.this.id
}

output "workspace_arn" {
  description = "AMP workspace ARN (used by the Grafana data source + IAM)"
  value       = aws_prometheus_workspace.this.arn
}

output "remote_write_url" {
  description = "Remote-write endpoint (Prometheus servers/containers push here)"
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "query_url" {
  description = "Query endpoint (Grafana / PromQL clients read here)"
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/query"
}

output "sns_topic_arn" {
  description = "SNS topic receiving AMP alerts"
  value       = aws_sns_topic.alerts.arn
}
