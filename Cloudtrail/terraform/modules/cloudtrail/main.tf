# -----------------------------------------------------------------------------
# cloudtrail — The trail
#
# Captures:
#   - Management events (control-plane: Create/Delete/Modify API calls) — free
#   - Data events (object/item-level) — only for resources you name; billed
#   - Insights events — anomaly detection on call-rate / error-rate; billed
#
# Key features for the exam objectives:
#   - is_multi_region_trail         → "global vs regional trails"
#   - include_global_service_events → IAM/STS/CloudFront (only emit in us-east-1)
#   - enable_log_file_validation    → "ensure logs have not been modified"
#   - advanced_event_selector       → "management vs data events"
#   - insight_selector              → "CloudTrail Insights"
#   - cloud_watch_logs_*            → "integrate with CloudWatch Logs"
# -----------------------------------------------------------------------------

locals {
  # CloudWatch Logs delivery is enabled only when BOTH the group ARN and role
  # ARN are provided (wired up in Checkpoint 4).
  cwlogs_enabled = var.cloudwatch_logs_group_arn != "" && var.cloudwatch_logs_role_arn != ""

  dynamodb_data_events = var.data_event_dynamodb_table_arn != ""
  lambda_data_events   = length(var.data_event_lambda_function_arns) > 0
}

resource "aws_cloudtrail" "this" {
  name           = "${var.prefix}-trail"
  s3_bucket_name = var.s3_bucket_name
  kms_key_id     = var.kms_key_arn

  # --- Scope -----------------------------------------------------------------
  is_multi_region_trail         = var.is_multi_region_trail
  include_global_service_events = true # IAM, STS, CloudFront, Route53, etc.

  # --- Integrity -------------------------------------------------------------
  # Writes hourly digest files signed so you can prove logs weren't tampered.
  enable_log_file_validation = true

  # --- CloudWatch Logs delivery (Checkpoint 4) -------------------------------
  # CloudTrail needs the "arn:...:*" form for the log group ARN.
  cloud_watch_logs_group_arn = local.cwlogs_enabled ? "${var.cloudwatch_logs_group_arn}:*" : null
  cloud_watch_logs_role_arn  = local.cwlogs_enabled ? var.cloudwatch_logs_role_arn : null

  # --- Event selectors -------------------------------------------------------
  # Using advanced_event_selector (the current console/API style).

  # (1) Management events — always on, both read and write.
  advanced_event_selector {
    name = "Management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # (2) DynamoDB data events — only when a table ARN is supplied.
  dynamic "advanced_event_selector" {
    for_each = local.dynamodb_data_events ? [1] : []
    content {
      name = "DynamoDB data events"
      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }
      field_selector {
        field  = "resources.type"
        equals = ["AWS::DynamoDB::Table"]
      }
      field_selector {
        field  = "resources.ARN"
        equals = [var.data_event_dynamodb_table_arn]
      }
    }
  }

  # (3) Lambda Invoke data events — only when function ARNs are supplied.
  dynamic "advanced_event_selector" {
    for_each = local.lambda_data_events ? [1] : []
    content {
      name = "Lambda data events"
      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }
      field_selector {
        field  = "resources.type"
        equals = ["AWS::Lambda::Function"]
      }
      field_selector {
        field  = "resources.ARN"
        equals = var.data_event_lambda_function_arns
      }
    }
  }

  # --- Insights --------------------------------------------------------------
  dynamic "insight_selector" {
    for_each = var.enable_insights ? ["ApiCallRateInsight", "ApiErrorRateInsight"] : []
    content {
      insight_type = insight_selector.value
    }
  }

  tags = { Name = "${var.prefix}-trail" }
}
