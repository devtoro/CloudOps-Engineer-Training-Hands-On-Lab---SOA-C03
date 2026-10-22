# -----------------------------------------------------------------------------
# autoheal-ssm module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-eb-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region (for building the SSM document ARN)"
  type        = string
}

variable "instance_id" {
  description = "EC2 instance id to auto-heal (restart)"
  type        = string
}
