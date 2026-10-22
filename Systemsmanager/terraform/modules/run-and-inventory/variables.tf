# -----------------------------------------------------------------------------
# run-and-inventory module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-ssm-dev)"
  type        = string
}

variable "instance_id" {
  description = "The managed instance to target"
  type        = string
}
