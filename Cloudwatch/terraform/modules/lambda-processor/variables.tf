# -----------------------------------------------------------------------------
# Lambda Processor module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-lab-dev)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 10
}

variable "source_dir" {
  description = "Path to the handler source directory (relative to the Terraform root dir)"
  type        = string
  default     = "../src/processor"
}
