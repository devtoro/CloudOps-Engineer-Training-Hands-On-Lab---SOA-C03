# -----------------------------------------------------------------------------
# Project-wide variables for the CloudTrail lab
# Pattern: {project_name}-{environment}-{resource}
# Example: cloudops-trail-dev-logs-bucket
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "cloudops-trail"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI / SSO profile name"
  type        = string
  default     = "dev"
}

# -----------------------------------------------------------------------------
# Trail behavior
# -----------------------------------------------------------------------------

variable "is_multi_region_trail" {
  description = "If true, the trail captures events from all regions (recommended)."
  type        = bool
  default     = true
}

variable "enable_insights" {
  description = "Enable CloudTrail Insights (detects unusual API call-rate / error-rate). NOTE: Insights analysis incurs extra cost (~$0.0035 per analyzed event type)."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Days to retain CloudTrail logs in the S3 bucket before expiry."
  type        = number
  default     = 365
}

variable "cwlogs_retention_days" {
  description = "Days to retain CloudTrail events in CloudWatch Logs."
  type        = number
  default     = 14
}

# -----------------------------------------------------------------------------
# Data event targets (default to Phase 1 Cloudwatch-lab resource names).
# Leave empty to skip that data event selector.
# These are plain names, NOT cross-state references, so the two labs stay
# independent. If the Phase 1 lab is redeployed, these targets light up.
# -----------------------------------------------------------------------------

variable "data_event_dynamodb_table_arn" {
  description = "ARN of a DynamoDB table to record data events for. Empty = skip."
  type        = string
  default     = ""
}

variable "data_event_lambda_function_arns" {
  description = "List of Lambda function ARNs to record Invoke data events for. Empty = skip."
  type        = list(string)
  default     = []
}
