# -----------------------------------------------------------------------------
# config-rules module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-config-dev)"
  type        = string
}

variable "required_tag_keys" {
  description = "Tag keys enforced by the required-tags managed rule (max 6)."
  type        = list(string)
  default     = ["Project", "Environment"]
}

variable "forbidden_bucket_substring" {
  description = "Custom rule flags S3 buckets whose name contains this substring."
  type        = string
  default     = "public"
}

variable "custom_rule_source_dir" {
  description = "Path to the custom rule Lambda source (relative to Terraform root dir)."
  type        = string
  default     = "../src/s3_naming_rule"
}
