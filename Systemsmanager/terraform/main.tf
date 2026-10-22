# =============================================================================
# Root module — AWS Systems Manager lab
#
# Modules:
#   managed-instance       → EC2 + SSM agent + instance profile (the managed node)
#   session-manager        → Session Manager logging prefs (S3 + CloudWatch Logs)
#   patch-manager          → patch baseline + patch group + maintenance window (SCAN)
#   run-and-inventory      → Run Command association + Inventory association
#   automation-eventbridge → custom Automation document + EventBridge trigger
#
# Hybrid activation (manage on-prem / non-EC2 nodes) is shown as REFERENCE code
# inside managed-instance (commented) — it needs a real on-prem machine to
# register, so it can't be exercised in this account alone.
#
# You've already met SSM across other labs: Automation docs (Config remediation,
# EventBridge auto-heal) and Parameter Store (AMI lookup). This lab assembles the
# full toolbox.
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — managed instance (EC2 + agent + profile)
# -----------------------------------------------------------------------------
module "managed_instance" {
  source        = "./modules/managed-instance"
  prefix        = local.prefix
  instance_type = var.instance_type
  patch_group   = var.patch_group
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — Session Manager logging (S3 + CloudWatch Logs)
# -----------------------------------------------------------------------------
module "session_manager" {
  source             = "./modules/session-manager"
  prefix             = local.prefix
  account_id         = data.aws_caller_identity.current.account_id
  instance_role_name = module.managed_instance.instance_role_name
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — Patch Manager (baseline + patch group + maintenance window)
# -----------------------------------------------------------------------------
module "patch_manager" {
  source      = "./modules/patch-manager"
  prefix      = local.prefix
  patch_group = var.patch_group
}

# -----------------------------------------------------------------------------
# Checkpoint 5 — Run Command + Inventory associations
# -----------------------------------------------------------------------------
module "run_and_inventory" {
  source      = "./modules/run-and-inventory"
  prefix      = local.prefix
  instance_id = module.managed_instance.instance_id
}

# -----------------------------------------------------------------------------
# Checkpoint 6 — custom Automation document + EventBridge trigger
# -----------------------------------------------------------------------------
module "automation_eventbridge" {
  source     = "./modules/automation-eventbridge"
  prefix     = local.prefix
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}
