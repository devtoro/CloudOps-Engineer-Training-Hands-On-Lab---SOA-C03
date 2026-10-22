# -----------------------------------------------------------------------------
# topics module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-sns-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}
