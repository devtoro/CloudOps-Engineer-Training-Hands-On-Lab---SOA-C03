# -----------------------------------------------------------------------------
# delivery-policy module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-sns-dev)"
  type        = string
}

variable "standard_topic_arn" {
  description = "ARN of the standard SNS topic"
  type        = string
}

variable "https_endpoint" {
  description = "HTTPS endpoint for the retry/backoff demo subscription (placeholder OK)"
  type        = string
}

variable "dlq_arn" {
  description = "ARN of the DLQ to alarm on (depth of failed deliveries)"
  type        = string
}

variable "dlq_name" {
  description = "Name of the DLQ (for the CloudWatch metric dimension)"
  type        = string
}
