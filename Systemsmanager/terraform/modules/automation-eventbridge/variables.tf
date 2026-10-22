# -----------------------------------------------------------------------------
# automation-eventbridge module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-ssm-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region (for the automation document ARN)"
  type        = string
}
