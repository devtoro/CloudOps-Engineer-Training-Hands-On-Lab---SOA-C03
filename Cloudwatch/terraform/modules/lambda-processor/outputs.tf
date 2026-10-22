# -----------------------------------------------------------------------------
# Lambda Processor module — outputs
# EventBridge needs function_arn for its target + lambda permission.
# -----------------------------------------------------------------------------

output "function_name" {
  description = "Name of the Processor Lambda function"
  value       = aws_lambda_function.processor.function_name
}

output "function_arn" {
  description = "ARN of the Processor Lambda function"
  value       = aws_lambda_function.processor.arn
}
