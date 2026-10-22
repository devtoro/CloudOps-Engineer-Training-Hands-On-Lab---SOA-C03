# -----------------------------------------------------------------------------
# session-manager module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-ssm-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID (for the S3 bucket name)"
  type        = string
}

variable "instance_role_name" {
  description = "Name of the managed instance's IAM role — needs log-write perms"
  type        = string
}

variable "cwlogs_retention_days" {
  description = "Retention for the Session Manager CloudWatch log group"
  type        = number
  default     = 30
}
