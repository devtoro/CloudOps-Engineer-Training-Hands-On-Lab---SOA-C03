# -----------------------------------------------------------------------------
# cloudtrail-cwlogs module — outputs
# The cloudtrail module needs log_group_arn + role_arn to enable delivery.
# -----------------------------------------------------------------------------

output "log_group_name" {
  description = "Name of the CloudWatch Logs group receiving CloudTrail events"
  value       = aws_cloudwatch_log_group.trail.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Logs group (without the :* suffix)"
  value       = aws_cloudwatch_log_group.trail.arn
}

output "role_arn" {
  description = "ARN of the IAM role CloudTrail assumes to write to CWL"
  value       = aws_iam_role.cloudtrail_cwlogs.arn
}
