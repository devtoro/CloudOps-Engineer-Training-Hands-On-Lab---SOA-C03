# =============================================================================
# Root module — EventBridge lab
#
# Modules (added one checkpoint at a time):
#   demo-target          → EC2 instance to auto-heal + SNS topic + Lambda log-target
#   rules-patterns       → rules demonstrating event-pattern matching variety
#   autoheal-ssm         → EC2 status event → SSM AWS-RestartEC2Instance (+ DLQ)
#   alarm-to-eventbridge → CloudWatch alarm → EventBridge rule → SSM auto-heal
#   cross-region         → custom bus (primary) forwards events to a bus in eu-west-1
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — demo target (EC2 + SNS + Lambda log-target)
# -----------------------------------------------------------------------------
module "demo_target" {
  source        = "./modules/demo-target"
  prefix        = local.prefix
  instance_type = var.instance_type
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — pattern-matching rules
# -----------------------------------------------------------------------------
module "rules_patterns" {
  source          = "./modules/rules-patterns"
  prefix          = local.prefix
  log_target_arn  = module.demo_target.log_lambda_arn
  log_target_name = module.demo_target.log_lambda_name
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — auto-heal via SSM Automation
# -----------------------------------------------------------------------------
module "autoheal_ssm" {
  source      = "./modules/autoheal-ssm"
  prefix      = local.prefix
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  instance_id = module.demo_target.instance_id
}

# -----------------------------------------------------------------------------
# Checkpoint 5 — CloudWatch alarm → EventBridge → auto-heal
# -----------------------------------------------------------------------------
module "alarm_to_eventbridge" {
  source                 = "./modules/alarm-to-eventbridge"
  prefix                 = local.prefix
  instance_id            = module.demo_target.instance_id
  ssm_document_arn       = module.autoheal_ssm.ssm_document_arn
  events_invoke_role_arn = module.autoheal_ssm.events_invoke_role_arn
  automation_role_arn    = module.autoheal_ssm.automation_role_arn
}

# -----------------------------------------------------------------------------
# Checkpoint 6 — cross-Region bus forwarding (eu-central-1 → eu-west-1)
# -----------------------------------------------------------------------------
module "cross_region" {
  source     = "./modules/cross-region"
  prefix     = local.prefix
  account_id = data.aws_caller_identity.current.account_id
  providers = {
    aws           = aws
    aws.secondary = aws.secondary
  }
}
