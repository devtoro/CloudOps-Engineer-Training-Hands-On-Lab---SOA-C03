# -----------------------------------------------------------------------------
# findings-export module — outputs
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "S3 bucket receiving exported Security Hub findings"
  value       = aws_s3_bucket.findings.id
}

output "firehose_name" {
  description = "Firehose delivery stream name"
  value       = aws_kinesis_firehose_delivery_stream.findings.name
}

output "rule_name" {
  description = "EventBridge rule capturing imported findings"
  value       = aws_cloudwatch_event_rule.findings.name
}
