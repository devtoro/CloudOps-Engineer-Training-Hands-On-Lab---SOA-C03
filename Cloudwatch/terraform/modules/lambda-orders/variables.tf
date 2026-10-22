# -----------------------------------------------------------------------------
# Lambda Orders module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-lab-dev)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB orders table"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB orders table (for IAM policy)"
  type        = string
}

variable "event_bus_name" {
  description = "EventBridge bus name to emit events to"
  type        = string
  default     = "default"
}

variable "event_bus_arn" {
  description = "ARN of the EventBridge bus (for IAM policy)"
  type        = string
  default     = ""
}

variable "memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Lambda timeout in seconds — 10s allows the 'slow' path to complete"
  type        = number
  default     = 10
}

variable "source_dir" {
  description = "Path to the handler source directory (relative to the Terraform root dir)"
  type        = string
  default     = "../src/orders"
}
