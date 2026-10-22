# -----------------------------------------------------------------------------
# demo-target module — outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance that gets auto-healed"
  value       = aws_instance.target.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.target.arn
}

output "log_lambda_arn" {
  description = "ARN of the log-target Lambda (EventBridge rule target)"
  value       = aws_lambda_function.log_target.arn
}

output "log_lambda_name" {
  description = "Name of the log-target Lambda"
  value       = aws_lambda_function.log_target.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic (an alternate rule target)"
  value       = aws_sns_topic.notifications.arn
}
