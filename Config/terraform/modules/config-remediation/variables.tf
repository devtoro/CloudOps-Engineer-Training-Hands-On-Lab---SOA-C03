# -----------------------------------------------------------------------------
# config-remediation module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-config-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "config_rule_name" {
  description = "Name of the Config rule to attach remediation to (the SSE rule)"
  type        = string
}

variable "automatic" {
  description = "If true, remediation runs automatically when a resource is NON_COMPLIANT. If false, you trigger it manually from the console."
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm the remediation applies"
  type        = string
  default     = "AES256"
}
