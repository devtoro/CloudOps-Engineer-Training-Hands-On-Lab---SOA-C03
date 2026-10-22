# -----------------------------------------------------------------------------
# Project-wide variables for the Grafana + Prometheus lab
# Pattern: {project_name}-{environment}-{resource}
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-obs"
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
# Grafana
# -----------------------------------------------------------------------------
variable "grafana_admin_group_id" {
  description = "IAM Identity Center GROUP id to grant Grafana ADMIN (optional). Leave empty to assign users in the console after deploy."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Alerting
# -----------------------------------------------------------------------------
variable "alert_email" {
  description = "Email to subscribe to the AMP alert SNS topic (optional). Leave empty to add subscriptions manually."
  type        = string
  default     = ""
}
