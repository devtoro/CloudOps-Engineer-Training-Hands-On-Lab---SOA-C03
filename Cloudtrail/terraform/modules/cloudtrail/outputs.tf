# -----------------------------------------------------------------------------
# cloudtrail module — outputs
# -----------------------------------------------------------------------------

output "trail_name" {
  description = "Name of the CloudTrail trail"
  value       = aws_cloudtrail.this.name
}

output "trail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.this.arn
}
