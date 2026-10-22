# =============================================================================
# Root outputs — uncomment as modules are added at each checkpoint.
# =============================================================================

output "trail_bucket_name" {
  description = "S3 bucket holding CloudTrail logs"
  value       = module.trail_s3.bucket_name
}

output "trail_kms_key_arn" {
  description = "KMS key used to encrypt CloudTrail logs"
  value       = module.trail_s3.kms_key_arn
}

output "trail_name" {
  description = "Name of the CloudTrail trail"
  value       = module.cloudtrail.trail_name
}

output "trail_cloudwatch_log_group" {
  description = "CloudWatch Logs group receiving CloudTrail events"
  value       = module.cloudtrail_cwlogs.log_group_name
}
