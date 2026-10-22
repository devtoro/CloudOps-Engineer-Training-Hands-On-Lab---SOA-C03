# -----------------------------------------------------------------------------
# managed-instance module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-ssm-dev)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "patch_group" {
  description = "Value for the 'Patch Group' tag (ties the instance to the patch baseline)"
  type        = string
}
