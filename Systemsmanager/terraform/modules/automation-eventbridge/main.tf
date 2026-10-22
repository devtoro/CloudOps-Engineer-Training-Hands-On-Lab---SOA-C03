# -----------------------------------------------------------------------------
# automation-eventbridge — custom SSM Automation document + EventBridge trigger
#
# You've used AWS-MANAGED automation docs before (AWS-RestartEC2Instance,
# AWS-EnableS3BucketEncryption). Here we author a CUSTOM one and trigger it on a
# schedule via EventBridge.
#
# An SSM Automation DOCUMENT (schemaVersion 0.3) is a multi-step runbook. Steps
# use "actions" like aws:executeAwsApi, aws:runCommand, aws:branch, aws:sleep,
# aws:approve (manual gate), etc. Automation runs under an assumeRole.
#
# Pieces:
#   1. The custom document (schemaVersion 0.3) — tags instances carrying a tag.
#   2. The AutomationAssumeRole the document runs as.
#   3. An EventBridge rule (scheduled) → starts the automation, via an
#      EventBridge-invoke role (ssm:StartAutomationExecution + iam:PassRole).
#
# CloudOps exam notes:
#   - Custom automation docs = schemaVersion "0.3", type "Automation".
#   - Automation needs an AutomationAssumeRole; EventBridge needs its own role
#     to start it + PassRole — the same two-role pattern as other SSM targets.
#   - Automations can also be triggered manually, by Config/Security Hub
#     remediation, or by maintenance windows.
# -----------------------------------------------------------------------------

# =============================================================================
# 1. The AutomationAssumeRole (what the runbook runs as)
# =============================================================================
resource "aws_iam_role" "automation" {
  name = "${var.prefix}-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-automation-role" }
}

# The document only tags EC2 instances, so grant just that.
resource "aws_iam_role_policy" "automation" {
  name = "${var.prefix}-automation-policy"
  role = aws_iam_role.automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:CreateTags", "ec2:DescribeInstances"]
      Resource = "*"
    }]
  })
}

# =============================================================================
# 2. The custom Automation document (schemaVersion 0.3)
#    Tags all instances that carry Patch Group tag with LastAutomationRun=<time>.
# =============================================================================
resource "aws_ssm_document" "remediation" {
  name            = "${var.prefix}-tag-instances"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-DOC
    schemaVersion: '0.3'
    description: >-
      Demo custom automation: tag the target instance with a timestamp. Stand-in
      for a real remediation (quarantine, restart, config fix, etc.).
    assumeRole: '{{ AutomationAssumeRole }}'
    parameters:
      InstanceId:
        type: String
        description: Instance to tag
      AutomationAssumeRole:
        type: String
        description: Role the automation assumes
    mainSteps:
      - name: TagInstance
        action: 'aws:executeAwsApi'
        inputs:
          Service: ec2
          Api: CreateTags
          Resources:
            - '{{ InstanceId }}'
          Tags:
            - Key: LastAutomationRun
              Value: '{{ global:DATE_TIME }}'
        isEnd: true
  DOC

  tags = { Name = "${var.prefix}-tag-instances" }
}

# =============================================================================
# 3. EventBridge rule (scheduled) → start the automation
# =============================================================================
resource "aws_iam_role" "events_invoke" {
  name = "${var.prefix}-events-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-events-automation-role" }
}

resource "aws_iam_role_policy" "events_invoke" {
  name = "${var.prefix}-events-automation-policy"
  role = aws_iam_role.events_invoke.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:StartAutomationExecution"]
        Resource = "arn:aws:ssm:${var.region}:${var.account_id}:automation-definition/${aws_ssm_document.remediation.name}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.automation.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" }
        }
      }
    ]
  })
}

# Scheduled trigger (hourly). Could equally be an event-pattern rule reacting to
# a Config/Security Hub/service event — same target wiring.
resource "aws_cloudwatch_event_rule" "trigger" {
  name                = "${var.prefix}-automation-trigger"
  description         = "Hourly trigger for the custom SSM Automation (demo)"
  schedule_expression = "rate(1 hour)"

  tags = { Name = "${var.prefix}-automation-trigger" }
}

resource "aws_cloudwatch_event_target" "automation" {
  rule     = aws_cloudwatch_event_rule.trigger.name
  arn      = "arn:aws:ssm:${var.region}:${var.account_id}:automation-definition/${aws_ssm_document.remediation.name}:$DEFAULT"
  role_arn = aws_iam_role.events_invoke.arn

  # EventBridge passes the automation's parameters here. InstanceId is left as a
  # placeholder you'd set to the managed node (or resolve via input transformer
  # on an event-driven rule).
  input = jsonencode({
    InstanceId           = ["REPLACE_WITH_INSTANCE_ID"]
    AutomationAssumeRole = [aws_iam_role.automation.arn]
  })
}
