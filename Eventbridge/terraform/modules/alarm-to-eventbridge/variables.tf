# -----------------------------------------------------------------------------
# alarm-to-eventbridge module — inputs
#
# This module reuses the SSM document + roles created by the autoheal-ssm
# module (passed in) — a clean example of module composition.
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-eb-dev)"
  type        = string
}

variable "instance_id" {
  description = "EC2 instance id the alarm watches + the auto-heal restarts"
  type        = string
}

variable "ssm_document_arn" {
  description = "ARN of the SSM Automation document (from autoheal-ssm)"
  type        = string
}

variable "events_invoke_role_arn" {
  description = "Role EventBridge assumes to start the automation (from autoheal-ssm)"
  type        = string
}

variable "automation_role_arn" {
  description = "AutomationAssumeRole the runbook runs as (from autoheal-ssm)"
  type        = string
}
