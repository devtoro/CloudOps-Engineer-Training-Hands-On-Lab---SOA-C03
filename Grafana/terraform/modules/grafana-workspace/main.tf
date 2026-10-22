# -----------------------------------------------------------------------------
# grafana-workspace — Amazon Managed Grafana (AMG)
#
# AMG is managed Grafana. Key facts:
#   - NO local username/password. Auth is IAM Identity Center (AWS_SSO) or SAML.
#   - AMG reads data sources using an IAM ROLE (service-managed or customer).
#     Here we provide a CUSTOMER-managed role scoped to CloudWatch, X-Ray, AMP.
#   - Users/groups are granted ADMIN / EDITOR / VIEWER via role assignments.
#
# This module creates:
#   - the workspace (SSO auth, CURRENT_ACCOUNT, data sources CloudWatch/X-Ray/AMP)
#   - the IAM role AMG assumes + a policy granting read access to those sources
#   - an optional ADMIN role assignment to an Identity Center group
#
# AMG exam notes:
#   - permission_type SERVICE_MANAGED lets AMG manage the role's data-source
#     policies for you; CUSTOMER_MANAGED (used here) means you own the policy.
#   - account_access_type CURRENT_ACCOUNT vs ORGANIZATION (multi-account via
#     delegated admin + OUs).
#   - Login requires Identity Center users; roles map to Grafana ADMIN/EDITOR/VIEWER.
# -----------------------------------------------------------------------------

# =============================================================================
# IAM role AMG assumes to read data sources
# =============================================================================
resource "aws_iam_role" "grafana" {
  name = "${var.prefix}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-grafana-role" }
}

# Read access for the three data sources (least-privilege-ish for a lab).
resource "aws_iam_role_policy" "grafana" {
  name = "${var.prefix}-grafana-datasources"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatch"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetInsightRuleReport",
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "tag:GetResources",
        ]
        Resource = "*"
      },
      {
        Sid    = "XRay"
        Effect = "Allow"
        Action = [
          "xray:BatchGetTraces",
          "xray:GetTraceSummaries",
          "xray:GetTraceGraph",
          "xray:GetGroups",
          "xray:GetTimeSeriesServiceStatistics",
          "xray:GetInsightSummaries",
          "xray:GetServiceGraph",
        ]
        Resource = "*"
      },
      {
        Sid    = "Prometheus"
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata",
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# The AMG workspace
# =============================================================================
resource "aws_grafana_workspace" "this" {
  name                     = "${var.prefix}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  data_sources = ["CLOUDWATCH", "XRAY", "PROMETHEUS"]

  tags = { Name = "${var.prefix}-grafana" }
}

# =============================================================================
# Optional: grant an Identity Center GROUP the Grafana ADMIN role
# =============================================================================
resource "aws_grafana_role_association" "admin" {
  count        = var.admin_group_id != "" ? 1 : 0
  workspace_id = aws_grafana_workspace.this.id
  role         = "ADMIN"
  group_ids    = [var.admin_group_id]
}
