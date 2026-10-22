# -----------------------------------------------------------------------------
# trail-s3 module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-trail-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used in bucket name + policy conditions"
  type        = string
}

variable "region" {
  description = "AWS region — used in the KMS key policy EncryptionContext"
  type        = string
}

variable "trail_name" {
  description = "Name of the trail that will write to this bucket (used in KMS + bucket policy conditions to scope access tightly)"
  type        = string
}

variable "log_retention_days" {
  description = "Days to retain log objects before the lifecycle rule expires them"
  type        = number
  default     = 365
}
