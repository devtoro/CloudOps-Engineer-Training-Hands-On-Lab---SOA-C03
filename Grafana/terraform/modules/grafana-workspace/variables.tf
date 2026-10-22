# -----------------------------------------------------------------------------
# grafana-workspace module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-obs-dev)"
  type        = string
}

variable "amp_workspace_arn" {
  description = "AMP workspace ARN the Grafana role may query"
  type        = string
}

variable "admin_group_id" {
  description = "IAM Identity Center GROUP id to grant Grafana ADMIN. Empty = assign in console."
  type        = string
  default     = ""
}
