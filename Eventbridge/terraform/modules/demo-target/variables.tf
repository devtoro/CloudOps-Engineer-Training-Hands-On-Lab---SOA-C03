# -----------------------------------------------------------------------------
# demo-target module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-eb-dev)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the auto-heal demo target"
  type        = string
  default     = "t3.micro"
}

variable "log_target_source_dir" {
  description = "Path to the log-target Lambda source (relative to Terraform root dir)"
  type        = string
  default     = "../src/log_target"
}
