# -----------------------------------------------------------------------------
# config-recorder module — outputs
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "S3 bucket storing Config snapshots + history"
  value       = aws_s3_bucket.config.id
}

output "bucket_arn" {
  description = "ARN of the Config S3 bucket"
  value       = aws_s3_bucket.config.arn
}

output "recorder_name" {
  description = "Name of the configuration recorder"
  value       = aws_config_configuration_recorder.this.name
}

output "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes"
  value       = aws_iam_role.config.arn
}
