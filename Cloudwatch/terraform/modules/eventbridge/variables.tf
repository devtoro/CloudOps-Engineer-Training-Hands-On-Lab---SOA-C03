# -----------------------------------------------------------------------------
# EventBridge module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-lab-dev)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "processor_lambda_arn" {
  description = "ARN of the Processor Lambda function (target for the rule)"
  type        = string
}
