# -----------------------------------------------------------------------------
# securityhub-core — Enable Security Hub, subscribe to standards, GuardDuty
#
# Security Hub is the AGGREGATION layer: it ingests findings from AWS services
# (GuardDuty, Inspector, Macie, IAM Access Analyzer, Config) and third-party
# products, normalizes them to the AWS Security Finding Format (ASFF), and runs
# compliance STANDARDS (sets of controls) producing a security score.
#
# CloudOps exam notes:
#   - Enabling the account is one resource; each STANDARD is a separate
#     subscription with its own region-specific ARN.
#   - FSBP and CIS controls are largely backed by AWS CONFIG rules — Config's
#     recorder should be ON for accurate results.
#   - GuardDuty is enabled separately; its findings flow INTO Security Hub via a
#     built-in integration (no manual wiring once both are on in the account).
# -----------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_partition" "current" {}

# =============================================================================
# 1. Enable Security Hub in this account/region
# =============================================================================
resource "aws_securityhub_account" "this" {
  # Control-finding generator + consolidated control findings are modern
  # defaults; left at provider defaults here for reference clarity.
  enable_default_standards = false # we subscribe explicitly below
}

# =============================================================================
# 2. Standards subscriptions
#
# Standard ARNs are region-specific. Format differs per standard:
#   FSBP: arn:aws:securityhub:<region>::standards/aws-foundational-security-best-practices/v/1.0.0
#   CIS : arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0  (global ruleset ARN)
# (CIS v1.2.0 uses the global ruleset ARN; newer CIS versions use a region ARN.)
# =============================================================================

resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_fsbp ? 1 : 0
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_cis ? 1 : 0
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
  depends_on    = [aws_securityhub_account.this]
}

# =============================================================================
# 3. Cross-Region finding aggregation
#    Designate this as the aggregation Region (all linked Regions roll up here).
# =============================================================================
resource "aws_securityhub_finding_aggregator" "this" {
  linking_mode = "ALL_REGIONS"
  depends_on   = [aws_securityhub_account.this]
}

# =============================================================================
# 4. GuardDuty as a finding source
#    Enabling GuardDuty in an account where Security Hub is on automatically
#    sends GuardDuty findings into Security Hub (built-in integration).
# =============================================================================
resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
  }

  tags = { Name = "${var.prefix}-guardduty" }
}

# The GuardDuty→Security Hub integration is enabled by default when both are on.
# If you ever need to manage it explicitly, this is the resource:
#
# resource "aws_securityhub_product_subscription" "guardduty" {
#   count       = var.enable_guardduty ? 1 : 0
#   product_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
#   depends_on  = [aws_securityhub_account.this, aws_guardduty_detector.this]
# }

# =============================================================================
# 5. THIRD-PARTY integrations (reference — concept)
#    Partner products (e.g. CrowdStrike, Palo Alto, Trend Micro) are subscribed
#    the same way, via a product subscription naming the partner's product ARN:
#
# resource "aws_securityhub_product_subscription" "partner" {
#   product_arn = "arn:aws:securityhub:<region>:<partner-account>:product/<company>/<product>"
#   depends_on  = [aws_securityhub_account.this]
# }

# =============================================================================
# 6. ORGANIZATION-LEVEL setup (reference — requires AWS Organizations)
#
# Would be run from the Organizations MANAGEMENT account. Not applicable in a
# single account, so left commented. Shows the real org pattern:
#
#   a) Designate a delegated administrator account for Security Hub:
#
# resource "aws_securityhub_organization_admin_account" "this" {
#   admin_account_id = "111122223333" # the security/audit account
# }
#
#   b) From the delegated admin, auto-enable Security Hub for all member
#      accounts (including future ones) and auto-enable standards:
#
# resource "aws_securityhub_organization_configuration" "this" {
#   auto_enable           = true
#   auto_enable_standards = "DEFAULT"
#   depends_on            = [aws_securityhub_organization_admin_account.this]
# }
#
# Exam angle: delegated admin + auto_enable = consistent coverage across the
# whole org, including accounts added later — the Control Tower / landing-zone
# pattern, mirroring how org CloudTrail and org Config work.
# =============================================================================
