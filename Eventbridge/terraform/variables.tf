# -----------------------------------------------------------------------------
# Project-wide variables for the EventBridge lab
# Pattern: {project_name}-{environment}-{resource}
# Example: cloudops-eb-dev-autoheal-rule
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-eb"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "secondary_region" {
  description = "Secondary region for the cross-Region bus-forwarding demo"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI / SSO profile name"
  type        = string
  default     = "dev"
}

# -----------------------------------------------------------------------------
# Demo target
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the auto-heal demo target (keep it tiny)"
  type        = string
  default     = "t3.micro"
}
