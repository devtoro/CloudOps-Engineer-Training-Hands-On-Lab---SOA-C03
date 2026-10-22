# =============================================================================
# Root outputs — uncomment as modules are added.
# =============================================================================

output "standard_topic_arn" {
  description = "Standard SNS topic ARN"
  value       = module.topics.standard_topic_arn
}

output "fifo_topic_arn" {
  description = "FIFO SNS topic ARN"
  value       = module.topics.fifo_topic_arn
}
#
output "orders_queue_url" {
  description = "SQS queue subscribed with a filter policy"
  value       = module.subscriptions.orders_queue_url
}

output "dlq_url" {
  description = "Dead-letter queue capturing failed deliveries"
  value       = module.subscriptions.dlq_url
}
