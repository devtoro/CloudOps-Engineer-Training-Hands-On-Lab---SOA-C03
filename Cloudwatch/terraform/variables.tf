# -----------------------------------------------------------------------------
# Project-wide variables
# These are passed down to every module to keep naming consistent.
# Pattern: {project_name}-{environment}-{resource}
# Example: cloudops-lab-dev-orders-table
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-lab"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI / SSO profile name"
  type        = string
  default     = "dev"
}
