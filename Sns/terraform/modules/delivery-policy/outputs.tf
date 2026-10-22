# -----------------------------------------------------------------------------
# delivery-policy module — outputs
# -----------------------------------------------------------------------------

output "https_subscription_arn" {
  description = "ARN of the HTTP/S subscription with the retry/backoff policy"
  value       = aws_sns_topic_subscription.https.arn
}

output "dlq_alarm_name" {
  description = "CloudWatch alarm watching DLQ depth"
  value       = aws_cloudwatch_metric_alarm.dlq_depth.alarm_name
}
