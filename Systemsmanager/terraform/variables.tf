# -----------------------------------------------------------------------------
# Project-wide variables for the Systems Manager lab
# Pattern: {project_name}-{environment}-{resource}
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-ssm"
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

variable "instance_type" {
  description = "EC2 instance type for the managed node (keep it tiny)"
  type        = string
  default     = "t3.micro"
}

# -----------------------------------------------------------------------------
# Patch group tag value — ties the instance to the patch baseline + maintenance
# window. Patch Manager groups instances by the tag key "Patch Group".
# -----------------------------------------------------------------------------
variable "patch_group" {
  description = "Patch Group tag value for the managed instance"
  type        = string
  default     = "cloudops-ssm-dev"
}
