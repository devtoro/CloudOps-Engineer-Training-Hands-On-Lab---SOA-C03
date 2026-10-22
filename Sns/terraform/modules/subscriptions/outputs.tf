# -----------------------------------------------------------------------------
# subscriptions module — outputs
# -----------------------------------------------------------------------------

output "orders_queue_url" {
  description = "SQS queue subscribed with the orders filter policy"
  value       = aws_sqs_queue.orders.url
}

output "alerts_queue_url" {
  description = "SQS queue subscribed with the alerts filter policy"
  value       = aws_sqs_queue.alerts.url
}

output "dlq_url" {
  description = "Dead-letter queue capturing failed SNS deliveries"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead-letter queue"
  value       = aws_sqs_queue.dlq.name
}

output "subscriber_lambda_name" {
  description = "Lambda subscriber function name"
  value       = aws_lambda_function.subscriber.function_name
}
