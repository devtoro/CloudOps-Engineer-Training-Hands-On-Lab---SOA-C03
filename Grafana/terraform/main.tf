# =============================================================================
# Root module — Amazon Managed Grafana (AMG) + Amazon Managed Prometheus (AMP)
#
# Modules:
#   prometheus-workspace → AMP workspace + alert manager + rules + SNS + IAM
#   grafana-workspace    → AMG workspace + IAM role + data sources
#                          (CloudWatch, X-Ray, AMP) + IAM Identity Center auth
#
# Deployable. Prereq: IAM Identity Center enabled in the account (for AMG login).
# The EKS/Kubernetes pieces (Prometheus server, exporters, remote write,
# multi-cluster/hybrid) are REFERENCE-ONLY in docs/ — not provisioned here.
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Checkpoint 2 — Amazon Managed Prometheus (workspace + alerting + SNS)
# -----------------------------------------------------------------------------
module "prometheus_workspace" {
  source      = "./modules/prometheus-workspace"
  prefix      = local.prefix
  alert_email = var.alert_email
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — Amazon Managed Grafana (workspace + data sources + SSO)
# -----------------------------------------------------------------------------
module "grafana_workspace" {
  source            = "./modules/grafana-workspace"
  prefix            = local.prefix
  admin_group_id    = var.grafana_admin_group_id
  amp_workspace_arn = module.prometheus_workspace.workspace_arn
}
