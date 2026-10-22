# -----------------------------------------------------------------------------
# subscriptions module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-sns-dev)"
  type        = string
}

variable "standard_topic_arn" {
  description = "ARN of the standard SNS topic to subscribe to"
  type        = string
}

variable "subscriber_source_dir" {
  description = "Path to the subscriber Lambda source (relative to Terraform root dir)"
  type        = string
  default     = "../src/subscriber"
}
