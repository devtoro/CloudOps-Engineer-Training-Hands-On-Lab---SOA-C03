# =============================================================================
# Root module — AWS Security Hub lab (REFERENCE CODE — validated, not deployed)
#
# Modules:
#   securityhub-core   → enable Security Hub, subscribe to standards, GuardDuty
#                        source, org-level resources (shown/commented)
#   findings-export    → EventBridge (Security Hub findings) → Firehose → S3
#                        (Lambda alternative commented out)
#   finding-response   → EventBridge rule on HIGH/CRITICAL findings → Lambda
#                        (SSM Automation alternative commented out)
#
# Dependency note: Security Hub's FSBP/CIS standards are largely implemented as
# AWS CONFIG rules. For meaningful control findings, the Config recorder must be
# running (see the Config lab). Security Hub + Config are tightly coupled.
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — Security Hub core (enable + standards + GuardDuty)
# -----------------------------------------------------------------------------
module "securityhub_core" {
  source           = "./modules/securityhub-core"
  prefix           = local.prefix
  enable_fsbp      = var.enable_fsbp
  enable_cis       = var.enable_cis
  enable_guardduty = var.enable_guardduty
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — findings export to S3 (EventBridge → Firehose → S3)
# -----------------------------------------------------------------------------
module "findings_export" {
  source     = "./modules/findings-export"
  prefix     = local.prefix
  account_id = data.aws_caller_identity.current.account_id
  depends_on = [module.securityhub_core]
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — automated incident response (EventBridge → Lambda)
# -----------------------------------------------------------------------------
module "finding_response" {
  source                   = "./modules/finding-response"
  prefix                   = local.prefix
  response_severity_labels = var.response_severity_labels
  depends_on               = [module.securityhub_core]
}
