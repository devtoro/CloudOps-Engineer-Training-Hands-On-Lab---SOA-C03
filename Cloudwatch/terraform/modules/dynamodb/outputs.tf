# -----------------------------------------------------------------------------
# DynamoDB module — outputs
# Other modules (lambda-orders) need the table name and ARN.
# -----------------------------------------------------------------------------

output "table_name" {
  description = "Name of the orders DynamoDB table"
  value       = aws_dynamodb_table.orders.name
}

output "table_arn" {
  description = "ARN of the orders DynamoDB table"
  value       = aws_dynamodb_table.orders.arn
}
