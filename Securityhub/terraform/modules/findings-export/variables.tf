# -----------------------------------------------------------------------------
# findings-export module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-sh-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}
