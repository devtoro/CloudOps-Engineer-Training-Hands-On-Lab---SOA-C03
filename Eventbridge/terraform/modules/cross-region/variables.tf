# -----------------------------------------------------------------------------
# cross-region module — inputs
#
# This module uses TWO providers: the default (primary region) and
# aws.secondary (the destination region). They are passed in from root via a
# `providers = { aws = aws, aws.secondary = aws.secondary }` block.
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Resource naming prefix (e.g. cloudops-eb-dev)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID (same account, cross-Region demo)"
  type        = string
}
