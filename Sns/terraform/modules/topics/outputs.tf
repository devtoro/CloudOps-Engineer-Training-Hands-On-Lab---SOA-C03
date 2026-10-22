# -----------------------------------------------------------------------------
# topics module — outputs
# -----------------------------------------------------------------------------

output "standard_topic_arn" {
  description = "Standard SNS topic ARN"
  value       = aws_sns_topic.standard.arn
}

output "fifo_topic_arn" {
  description = "FIFO SNS topic ARN"
  value       = aws_sns_topic.fifo.arn
}

output "kms_key_arn" {
  description = "KMS key encrypting the topics"
  value       = aws_kms_key.sns.arn
}
