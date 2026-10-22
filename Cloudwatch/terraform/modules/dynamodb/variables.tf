# -----------------------------------------------------------------------------
# DynamoDB module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-lab-dev)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "read_capacity" {
  description = "Provisioned read capacity units — keep low to trigger throttling"
  type        = number
  default     = 1
}

variable "write_capacity" {
  description = "Provisioned write capacity units — keep low to trigger throttling"
  type        = number
  default     = 1
}
