# =============================================================================
# Root module — CloudTrail lab
#
# Wires together three modules:
#   trail-s3          → where logs are stored (S3 + KMS + policies + lifecycle)
#   cloudtrail        → the trail itself (event selectors, validation, Insights)
#   cloudtrail-cwlogs → CloudWatch Logs integration for real-time analysis
#
# Modules are added one checkpoint at a time.
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

# Account ID + region, used in bucket policies and ARNs
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — S3 storage (bucket + KMS + policies + lifecycle)
# -----------------------------------------------------------------------------
module "trail_s3" {
  source             = "./modules/trail-s3"
  prefix             = local.prefix
  account_id         = data.aws_caller_identity.current.account_id
  region             = data.aws_region.current.name
  log_retention_days = var.log_retention_days
  trail_name         = "${local.prefix}-trail"
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — CloudWatch Logs integration
# -----------------------------------------------------------------------------
module "cloudtrail_cwlogs" {
  source         = "./modules/cloudtrail-cwlogs"
  prefix         = local.prefix
  retention_days = var.cwlogs_retention_days
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — the Trail
# -----------------------------------------------------------------------------
module "cloudtrail" {
  source                = "./modules/cloudtrail"
  prefix                = local.prefix
  s3_bucket_name        = module.trail_s3.bucket_name
  kms_key_arn           = module.trail_s3.kms_key_arn
  is_multi_region_trail = var.is_multi_region_trail
  enable_insights       = var.enable_insights

  # CloudWatch Logs delivery
  cloudwatch_logs_group_arn = module.cloudtrail_cwlogs.log_group_arn
  cloudwatch_logs_role_arn  = module.cloudtrail_cwlogs.role_arn

  data_event_dynamodb_table_arn   = var.data_event_dynamodb_table_arn
  data_event_lambda_function_arns = var.data_event_lambda_function_arns

  # The bucket policy must exist before CloudTrail runs its creation-time
  # write test, or trail creation fails.
  depends_on = [module.trail_s3]
}
