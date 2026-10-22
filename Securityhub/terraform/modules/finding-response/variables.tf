# -----------------------------------------------------------------------------
# finding-response module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-sh-dev)"
  type        = string
}

variable "response_severity_labels" {
  description = "Severity labels that trigger incident response"
  type        = list(string)
  default     = ["HIGH", "CRITICAL"]
}

variable "source_dir" {
  description = "Path to the responder Lambda source (relative to Terraform root dir)"
  type        = string
  default     = "../src/finding_response"
}
