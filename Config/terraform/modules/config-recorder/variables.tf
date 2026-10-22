# -----------------------------------------------------------------------------
# config-recorder module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-config-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used in bucket name + policy conditions"
  type        = string
}

variable "record_all_resource_types" {
  description = "Record all supported resource types + global resources"
  type        = bool
  default     = true
}

variable "snapshot_delivery_frequency" {
  description = "How often Config delivers a configuration snapshot to S3"
  type        = string
  default     = "TwentyFour_Hours"
}
