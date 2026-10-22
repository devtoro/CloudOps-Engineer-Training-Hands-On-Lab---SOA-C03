# =============================================================================
# Root module — AWS Config lab
#
# Wires together three modules in dependency order:
#   config-recorder     → S3 bucket + IAM role + recorder + delivery channel
#   config-rules        → managed rules (SSE, required-tags) + 1 custom Lambda rule
#   config-remediation  → SSM Automation remediation attached to the SSE rule
#
# IMPORTANT ordering:
#   The configuration recorder + delivery channel must exist and be running
#   BEFORE Config rules can evaluate. Rules depend on the recorder module.
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — Configuration recorder + delivery channel + storage
# -----------------------------------------------------------------------------
module "config_recorder" {
  source                    = "./modules/config-recorder"
  prefix                    = local.prefix
  account_id                = data.aws_caller_identity.current.account_id
  record_all_resource_types = var.record_all_resource_types
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — Config rules (managed + custom)
# -----------------------------------------------------------------------------
module "config_rules" {
  source            = "./modules/config-rules"
  prefix            = local.prefix
  required_tag_keys = var.required_tag_keys
  # Rules can only evaluate once the recorder is running.
  depends_on = [module.config_recorder]
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — Remediation (SSM Automation on the SSE rule)
# -----------------------------------------------------------------------------
module "config_remediation" {
  source           = "./modules/config-remediation"
  prefix           = local.prefix
  account_id       = data.aws_caller_identity.current.account_id
  config_rule_name = module.config_rules.sse_rule_name
  depends_on       = [module.config_rules]
}
