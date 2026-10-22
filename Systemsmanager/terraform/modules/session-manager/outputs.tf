# -----------------------------------------------------------------------------
# session-manager module — outputs
# -----------------------------------------------------------------------------

output "log_bucket" {
  description = "S3 bucket storing Session Manager session logs"
  value       = aws_s3_bucket.sessions.id
}

output "log_group" {
  description = "CloudWatch log group storing Session Manager session logs"
  value       = aws_cloudwatch_log_group.sessions.name
}
