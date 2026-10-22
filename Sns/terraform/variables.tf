# -----------------------------------------------------------------------------
# Project-wide variables for the SNS lab
# Pattern: {project_name}-{environment}-{resource}
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-sns"
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

# -----------------------------------------------------------------------------
# HTTP/S retry demo — placeholder endpoint (no live receiver needed to show the
# delivery/retry/backoff policy configuration).
# -----------------------------------------------------------------------------
variable "https_endpoint" {
  description = "HTTPS endpoint for the delivery-policy (retry/backoff) demo subscription"
  type        = string
  default     = "https://example.com/sns-endpoint"
}
