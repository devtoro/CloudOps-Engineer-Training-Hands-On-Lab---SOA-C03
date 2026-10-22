# -----------------------------------------------------------------------------
# trail-s3 module — outputs
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the CloudTrail logs bucket"
  value       = aws_s3_bucket.trail.id
}

output "bucket_arn" {
  description = "ARN of the CloudTrail logs bucket"
  value       = aws_s3_bucket.trail.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the logs"
  value       = aws_kms_key.trail.arn
}
