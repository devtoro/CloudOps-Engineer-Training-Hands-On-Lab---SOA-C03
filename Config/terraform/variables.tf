# -----------------------------------------------------------------------------
# Project-wide variables for the AWS Config lab
# Pattern: {project_name}-{environment}-{resource}
# Example: cloudops-config-dev-recorder
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-config"
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
# Recorder scope
# -----------------------------------------------------------------------------

variable "record_all_resource_types" {
  description = "If true, record ALL supported resource types (plus global resources). This is our lab choice. Set false to narrow via recording_group in the module."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Rule configuration
# -----------------------------------------------------------------------------

variable "required_tag_keys" {
  description = "Tag keys the required-tags managed rule enforces on taggable resources."
  type        = list(string)
  default     = ["Project", "Environment"]
}
