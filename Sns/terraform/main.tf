# =============================================================================
# Root module — Amazon SNS lab
#
# Modules:
#   topics          → standard + FIFO topics, KMS encryption, topic access policy
#   subscriptions   → SQS subscribers w/ FILTER POLICIES + per-subscription DLQ,
#                     plus a Lambda subscriber (visible processed target)
#   delivery-policy → HTTP/S subscription with a retry/backoff delivery policy
#                     (config demo against a placeholder URL)
#
# SNS has appeared as a notification target in earlier labs (Config, EventBridge,
# AMP). This lab covers it directly: topics, security, filtering, DLQs, retries.
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — topics (standard + FIFO, KMS, policy)
# -----------------------------------------------------------------------------
module "topics" {
  source     = "./modules/topics"
  prefix     = local.prefix
  account_id = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — subscriptions (SQS + filter policies + DLQ, Lambda)
# -----------------------------------------------------------------------------
module "subscriptions" {
  source             = "./modules/subscriptions"
  prefix             = local.prefix
  standard_topic_arn = module.topics.standard_topic_arn
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — HTTP/S delivery policy (retry/backoff) demo
# -----------------------------------------------------------------------------
module "delivery_policy" {
  source             = "./modules/delivery-policy"
  prefix             = local.prefix
  standard_topic_arn = module.topics.standard_topic_arn
  https_endpoint     = var.https_endpoint
  dlq_arn            = module.subscriptions.dlq_arn
  dlq_name           = module.subscriptions.dlq_name
}
