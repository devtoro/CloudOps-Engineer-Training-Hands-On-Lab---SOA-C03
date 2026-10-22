# -----------------------------------------------------------------------------
# API Gateway module — outputs
# -----------------------------------------------------------------------------

output "api_url" {
  description = "Base invoke URL of the deployed REST API stage"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "rest_api_id" {
  description = "ID of the REST API (useful for later dashboard/alarm modules)"
  value       = aws_api_gateway_rest_api.this.id
}

output "stage_name" {
  description = "Name of the deployed stage"
  value       = aws_api_gateway_stage.this.stage_name
}

output "api_key_value" {
  description = "The API key to send in x-api-key header"
  value       = aws_api_gateway_api_key.this.value
  sensitive   = true
}
