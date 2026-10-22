# -----------------------------------------------------------------------------
# cloudtrail module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-trail-dev)"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to deliver logs to"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt log files"
  type        = string
}

variable "is_multi_region_trail" {
  description = "Capture events from all regions"
  type        = bool
  default     = true
}

variable "enable_insights" {
  description = "Enable CloudTrail Insights (ApiCallRate + ApiErrorRate). Incurs extra cost."
  type        = bool
  default     = true
}

# --- CloudWatch Logs integration (supplied in Checkpoint 4) ------------------
# Both must be set together. When empty, the trail does not deliver to CWL.

variable "cloudwatch_logs_group_arn" {
  description = "CloudWatch Logs group ARN for real-time delivery. Empty = disabled."
  type        = string
  default     = ""
}

variable "cloudwatch_logs_role_arn" {
  description = "IAM role ARN CloudTrail assumes to write to CWL. Empty = disabled."
  type        = string
  default     = ""
}

# --- Data event targets ------------------------------------------------------

variable "data_event_dynamodb_table_arn" {
  description = "DynamoDB table ARN to record data events for. Empty = skip."
  type        = string
  default     = ""
}

variable "data_event_lambda_function_arns" {
  description = "Lambda function ARNs to record Invoke data events for. Empty = skip."
  type        = list(string)
  default     = []
}
