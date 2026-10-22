# =============================================================================
# Root outputs — surfaced after terraform apply
# Uncomment as modules are added at each checkpoint.
# =============================================================================

# -----------------------------------------------------------------------------
# API Gateway
# -----------------------------------------------------------------------------
output "api_url" {
  description = "Base URL of the REST API"
  value       = module.api_gateway.api_url
}

# -----------------------------------------------------------------------------
# DynamoDB
# -----------------------------------------------------------------------------
output "dynamodb_table_name" {
  description = "Name of the orders DynamoDB table"
  value       = module.dynamodb.table_name
}

# -----------------------------------------------------------------------------
# Lambda functions
# -----------------------------------------------------------------------------
output "orders_function_name" {
  description = "Name of the Orders Lambda function"
  value       = module.lambda_orders.function_name
}

output "processor_function_name" {
  description = "Name of the Processor Lambda function"
  value       = module.lambda_processor.function_name
}
