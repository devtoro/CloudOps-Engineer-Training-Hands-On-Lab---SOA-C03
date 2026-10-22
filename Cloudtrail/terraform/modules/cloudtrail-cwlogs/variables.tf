# -----------------------------------------------------------------------------
# cloudtrail-cwlogs module — inputs
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-trail-dev)"
  type        = string
}

variable "retention_days" {
  description = "Days to retain CloudTrail events in CloudWatch Logs (shorter than S3; CWL is for active analysis, S3 is the archive)"
  type        = number
  default     = 14
}
