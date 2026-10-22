# -----------------------------------------------------------------------------
# securityhub-core module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-sh-dev)"
  type        = string
}

variable "enable_fsbp" {
  description = "Subscribe to AWS Foundational Security Best Practices"
  type        = bool
  default     = true
}

variable "enable_cis" {
  description = "Subscribe to CIS AWS Foundations Benchmark"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable GuardDuty as a Security Hub finding source"
  type        = bool
  default     = true
}
