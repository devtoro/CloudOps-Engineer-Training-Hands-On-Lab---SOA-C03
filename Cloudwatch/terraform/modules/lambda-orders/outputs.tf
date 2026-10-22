# -----------------------------------------------------------------------------
# Lambda Orders module — outputs
# API Gateway needs invoke_arn. Root needs function_name for display.
# -----------------------------------------------------------------------------

output "function_name" {
  description = "Name of the Orders Lambda function"
  value       = aws_lambda_function.orders.function_name
}

output "function_arn" {
  description = "ARN of the Orders Lambda function"
  value       = aws_lambda_function.orders.arn
}

output "invoke_arn" {
  description = "Invoke ARN (used by API Gateway integration)"
  value       = aws_lambda_function.orders.invoke_arn
}
