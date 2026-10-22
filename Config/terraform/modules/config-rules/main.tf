# -----------------------------------------------------------------------------
# config-rules — Managed rules + one custom Lambda-backed rule
#
# A Config RULE evaluates configuration items and reports COMPLIANT /
# NON_COMPLIANT. Two source types:
#   - AWS MANAGED  → prebuilt by AWS, you just reference the identifier.
#   - CUSTOM_LAMBDA → you supply a Lambda that returns the verdict.
#   (There is also CUSTOM_POLICY using Guard, not used here.)
#
# Trigger types:
#   - Configuration changes → rule re-evaluates when a matching resource changes.
#   - Periodic              → rule re-evaluates on a schedule.
#
# CloudOps exam notes:
#   - Rules only evaluate while the RECORDER is running (hence module depends_on).
#   - A managed rule is identified by its sourceIdentifier (uppercase constant).
#   - A custom rule's Lambda must be granted permission for config to invoke it,
#     AND the Lambda needs config:PutEvaluations to report results back.
# -----------------------------------------------------------------------------

# =============================================================================
# Managed rule 1 — S3 default encryption enabled
# NON_COMPLIANT when a bucket has no default (server-side) encryption.
# This is the rule the remediation module auto-fixes.
# =============================================================================

resource "aws_config_config_rule" "s3_sse" {
  name = "${var.prefix}-s3-sse-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }
}

# =============================================================================
# Managed rule 2 — required tags
# NON_COMPLIANT when a taggable resource is missing the required tag keys.
# The managed rule takes tag keys as input parameters tag1Key..tag6Key.
# =============================================================================

resource "aws_config_config_rule" "required_tags" {
  name = "${var.prefix}-required-tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  # Map the provided keys to the managed rule's expected parameter names.
  input_parameters = jsonencode({
    for idx, key in var.required_tag_keys :
    "tag${idx + 1}Key" => key
  })
}

# =============================================================================
# Custom rule — S3 bucket naming (Lambda-backed, change-triggered)
# =============================================================================

# --- Package the Lambda ------------------------------------------------------

data "archive_file" "s3_naming" {
  type        = "zip"
  source_dir  = var.custom_rule_source_dir
  output_path = "${path.module}/s3_naming_rule.zip"
}

# --- Lambda execution role ---------------------------------------------------

resource "aws_iam_role" "s3_naming" {
  name = "${var.prefix}-s3-naming-rule-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-s3-naming-rule-role" }
}

# Logs + the all-important config:PutEvaluations (how the verdict reaches Config)
resource "aws_iam_role_policy" "s3_naming" {
  name = "${var.prefix}-s3-naming-rule-policy"
  role = aws_iam_role.s3_naming.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["config:PutEvaluations"]
        Resource = "*"
      }
    ]
  })
}

# --- The Lambda function -----------------------------------------------------

resource "aws_lambda_function" "s3_naming" {
  function_name = "${var.prefix}-s3-naming-rule"
  role          = aws_iam_role.s3_naming.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.s3_naming.output_path
  source_code_hash = data.archive_file.s3_naming.output_base64sha256

  environment {
    variables = {
      FORBIDDEN_SUBSTRING = var.forbidden_bucket_substring
    }
  }

  tags = { Name = "${var.prefix}-s3-naming-rule" }
}

# --- Allow the Config service to invoke the Lambda ---------------------------

resource "aws_lambda_permission" "config_invoke" {
  statement_id  = "AllowConfigInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_naming.function_name
  principal     = "config.amazonaws.com"
}

# --- The custom Config rule --------------------------------------------------

resource "aws_config_config_rule" "s3_naming" {
  name = "${var.prefix}-s3-naming-check"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.s3_naming.arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  # Only hand this rule S3 bucket configuration items.
  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }

  depends_on = [aws_lambda_permission.config_invoke]
}
