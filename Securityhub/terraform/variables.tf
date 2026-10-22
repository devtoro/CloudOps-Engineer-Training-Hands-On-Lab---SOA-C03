# -----------------------------------------------------------------------------
# Project-wide variables for the Security Hub lab (reference code)
# Pattern: {project_name}-{environment}-{resource}
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-sh"
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
# Standards toggles
# -----------------------------------------------------------------------------

variable "enable_fsbp" {
  description = "Subscribe to the AWS Foundational Security Best Practices standard"
  type        = bool
  default     = true
}

variable "enable_cis" {
  description = "Subscribe to the CIS AWS Foundations Benchmark standard"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable GuardDuty as a finding source for Security Hub (reference)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Incident-response filter
# -----------------------------------------------------------------------------

variable "response_severity_labels" {
  description = "Finding severity labels that trigger the incident-response rule"
  type        = list(string)
  default     = ["HIGH", "CRITICAL"]
}
