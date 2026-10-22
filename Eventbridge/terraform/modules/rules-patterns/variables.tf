# -----------------------------------------------------------------------------
# rules-patterns module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-eb-dev)"
  type        = string
}

variable "log_target_arn" {
  description = "ARN of the log-target Lambda (every demo rule routes here)"
  type        = string
}

variable "log_target_name" {
  description = "Name of the log-target Lambda (for lambda permission)"
  type        = string
}
