# -----------------------------------------------------------------------------
# patch-manager module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-ssm-dev)"
  type        = string
}

variable "patch_group" {
  description = "Patch Group tag value that ties instances to this baseline"
  type        = string
}

variable "maintenance_window_schedule" {
  description = "Cron/rate schedule for the maintenance window (UTC)"
  type        = string
  default     = "cron(0 3 ? * SUN *)" # 03:00 UTC every Sunday
}
