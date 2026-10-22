# -----------------------------------------------------------------------------
# finding-response — Automated incident response to Security Hub findings
#
# Flow:
#   Security Hub finding (HIGH/CRITICAL)
#     → EventBridge rule (filters by severity label)
#     → Lambda responder (acts on the finding)
#
# Severity filtering uses the ASFF path:
#   detail.findings[].Severity.Label  ∈  ["HIGH","CRITICAL"]
#
# An SSM Automation alternative is shown COMMENTED OUT below — use it when the
# response is a known runbook (e.g. isolate instance) rather than custom code.
#
# CloudOps exam notes:
#   - "Security Hub Findings - Imported" fires on new/updated findings.
#   - You filter on Severity.Label (CRITICAL/HIGH/MEDIUM/LOW/INFORMATIONAL) or
#     the numeric Severity.Normalized (0-100) to decide what warrants response.
#   - Pair with Security Hub "automation rules" to auto-suppress/triage, and
#     with custom actions for human-initiated response from the console.
# -----------------------------------------------------------------------------

# =============================================================================
# Responder Lambda
# =============================================================================
data "archive_file" "response" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/finding_response.zip"
}

resource "aws_iam_role" "response" {
  name = "${var.prefix}-response-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-response-role" }
}

resource "aws_iam_role_policy" "response_logs" {
  name = "${var.prefix}-response-logs"
  role = aws_iam_role.response.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_lambda_function" "response" {
  function_name = "${var.prefix}-finding-response"
  role          = aws_iam_role.response.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.response.output_path
  source_code_hash = data.archive_file.response.output_base64sha256

  tags = { Name = "${var.prefix}-finding-response" }
}

# =============================================================================
# EventBridge rule: HIGH/CRITICAL findings → Lambda
# =============================================================================
resource "aws_cloudwatch_event_rule" "response" {
  name        = "${var.prefix}-finding-response"
  description = "Route high-severity Security Hub findings to the responder"

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = var.response_severity_labels
        }
      }
    }
  })

  tags = { Name = "${var.prefix}-finding-response" }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.response.name
  target_id = "responder"
  arn       = aws_lambda_function.response.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.response.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.response.arn
}

# =============================================================================
# ALTERNATIVE target: SSM Automation runbook (commented out)
#
# When the response is a known, repeatable fix, target an SSM Automation doc
# instead of (or alongside) the Lambda. Needs an EventBridge-invoke role with
# ssm:StartAutomationExecution + iam:PassRole, and the runbook's own
# AutomationAssumeRole — exactly the two-role pattern from the EventBridge lab.
#
# resource "aws_cloudwatch_event_target" "ssm" {
#   rule     = aws_cloudwatch_event_rule.response.name
#   arn      = "arn:aws:ssm:<region>:<account>:automation-definition/AWS-DisablePublicAccessForSecurityGroup"
#   role_arn = aws_iam_role.events_invoke_ssm.arn   # ssm:StartAutomationExecution + iam:PassRole
#
#   input_transformer {
#     input_paths = {
#       groupId = "$.detail.findings[0].Resources[0].Id"
#     }
#     input_template = <<-EOT
#       {
#         "GroupId": [<groupId>],
#         "AutomationAssumeRole": ["arn:aws:iam::<account>:role/<automation-role>"]
#       }
#     EOT
#   }
# }
# =============================================================================
