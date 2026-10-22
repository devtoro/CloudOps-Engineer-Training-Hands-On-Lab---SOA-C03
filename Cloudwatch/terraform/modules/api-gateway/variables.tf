# -----------------------------------------------------------------------------
# API Gateway module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-lab-dev)"
  type        = string
}

variable "environment" {
  description = "Deployment environment — used as the stage name"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the Orders Lambda function (for lambda_permission)"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the Orders Lambda function (for integration URI)"
  type        = string
}

variable "api_key_value" {
  description = "Hard-coded API key value (minimum 20 characters for API Gateway)"
  type        = string
  default     = "manolis-cloudops-lab-key"
  sensitive   = true
}
