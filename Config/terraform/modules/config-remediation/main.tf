# -----------------------------------------------------------------------------
# config-remediation — Auto-fix non-compliant resources via SSM Automation
#
# Remediation flow:
#   Config rule finds a resource NON_COMPLIANT
#     → Config triggers an SSM Automation document
#     → the document (running under an IAM role we provide) fixes the resource
#     → the rule re-evaluates and (hopefully) flips to COMPLIANT
#
# We use the AWS-managed document "AWS-EnableS3BucketEncryption" to turn on
# default encryption for a bucket flagged by the s3-sse-enabled rule.
#
# CloudOps exam notes:
#   - Remediation can be AUTOMATIC (runs on its own) or MANUAL (you click
#     "Remediate" in the console). Automatic is powerful but risky — on a
#     misfiring rule it can make unwanted changes fleet-wide.
#   - The SSM document runs under an IAM ROLE YOU SUPPLY (AutomationAssumeRole).
#     That role — not Config — needs the permissions to perform the fix.
#   - resource_value with ResourceId maps the NON_COMPLIANT resource into the
#     document's target parameter automatically.
#   - maximum_automatic_attempts + retry window guard against flapping.
# -----------------------------------------------------------------------------

locals {
  # AWS-managed SSM Automation document that enables S3 default encryption.
  ssm_document_name = "AWS-EnableS3BucketEncryption"
}

# --- IAM role that SSM Automation assumes to perform the remediation ---------

resource "aws_iam_role" "remediation" {
  name = "${var.prefix}-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-remediation-role" }
}

# Permissions needed to enable S3 bucket encryption.
resource "aws_iam_role_policy" "remediation" {
  name = "${var.prefix}-remediation-policy"
  role = aws_iam_role.remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = "arn:aws:s3:::*"
      }
    ]
  })
}

# --- The remediation configuration -------------------------------------------

resource "aws_config_remediation_configuration" "s3_sse" {
  config_rule_name = var.config_rule_name

  target_type    = "SSM_DOCUMENT"
  target_id      = local.ssm_document_name
  target_version = "1"

  # Run automatically when a resource is found NON_COMPLIANT.
  automatic                  = var.automatic
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60

  # The role SSM Automation assumes to do the work.
  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.remediation.arn
  }

  # Map the NON_COMPLIANT bucket's resource id into the document's BucketName.
  parameter {
    name           = "BucketName"
    resource_value = "RESOURCE_ID"
  }

  # The encryption algorithm to apply.
  parameter {
    name         = "SSEAlgorithm"
    static_value = var.sse_algorithm
  }
}
