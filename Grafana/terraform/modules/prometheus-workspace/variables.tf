# -----------------------------------------------------------------------------
# prometheus-workspace module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-obs-dev)"
  type        = string
}

variable "alert_email" {
  description = "Optional email to subscribe to the alert SNS topic. Empty = skip."
  type        = string
  default     = ""
}
