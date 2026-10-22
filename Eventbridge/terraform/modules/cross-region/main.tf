# -----------------------------------------------------------------------------
# cross-region — Forward events from a bus in the primary region to a bus in
# the secondary region (eu-central-1 → eu-west-1, same account).
#
# How cross-Region/-account forwarding works in EventBridge:
#   You make ANOTHER EVENT BUS the TARGET of a rule.
#     - Source side: a rule whose target is the destination bus ARN, plus an
#       IAM role EventBridge assumes to call events:PutEvents on that bus.
#     - Destination side: a resource POLICY on the bus allowing the source
#       (account/region) to PutEvents.
#   The destination bus then runs its own rules on the forwarded events.
#
# For cross-ACCOUNT, the shape is identical — only the destination bus policy
# names a different account as principal. (Documented in concepts; here it's
# cross-Region, same account, which is fully deployable in one account.)
# -----------------------------------------------------------------------------

# This module needs the aws.secondary aliased provider in addition to the
# default. Root must pass both via the module's `providers` block.
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.secondary]
    }
  }
}

data "aws_region" "primary" {}
data "aws_region" "secondary" {
  provider = aws.secondary
}

# =============================================================================
# DESTINATION side (secondary region)
# =============================================================================

resource "aws_cloudwatch_event_bus" "destination" {
  provider = aws.secondary
  name     = "${var.prefix}-dest-bus"
  tags     = { Name = "${var.prefix}-dest-bus" }
}

# Resource policy: allow this account's EventBridge (from the primary region) to
# put events onto the destination bus.
resource "aws_cloudwatch_event_bus_policy" "destination" {
  provider       = aws.secondary
  event_bus_name = aws_cloudwatch_event_bus.destination.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCrossRegionPutEvents"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
      Action    = "events:PutEvents"
      Resource  = aws_cloudwatch_event_bus.destination.arn
    }]
  })
}

# A CloudWatch Logs group as the visible destination target, so you can confirm
# forwarded events actually arrived in the secondary region.
resource "aws_cloudwatch_log_group" "destination" {
  provider          = aws.secondary
  name              = "/aws/events/${var.prefix}-forwarded"
  retention_in_days = 7
}

# Rule on the DESTINATION bus: capture everything from the forwarded source and
# log it. (Matches the custom source we forward below.)
resource "aws_cloudwatch_event_rule" "destination" {
  provider       = aws.secondary
  name           = "${var.prefix}-dest-capture"
  event_bus_name = aws_cloudwatch_event_bus.destination.name
  event_pattern = jsonencode({
    source = ["myapp.crossregion"]
  })
}

resource "aws_cloudwatch_event_target" "destination_logs" {
  provider       = aws.secondary
  rule           = aws_cloudwatch_event_rule.destination.name
  event_bus_name = aws_cloudwatch_event_bus.destination.name
  target_id      = "to-logs"
  arn            = aws_cloudwatch_log_group.destination.arn
}

# Allow EventBridge (secondary region) to write to the log group.
resource "aws_cloudwatch_log_resource_policy" "destination" {
  provider    = aws.secondary
  policy_name = "${var.prefix}-dest-events-to-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.destination.arn}:*"
    }]
  })
}

# =============================================================================
# SOURCE side (primary region)
# =============================================================================

resource "aws_cloudwatch_event_bus" "source" {
  name = "${var.prefix}-source-bus"
  tags = { Name = "${var.prefix}-source-bus" }
}

# Role EventBridge assumes to forward events to the destination bus.
resource "aws_iam_role" "forward" {
  name = "${var.prefix}-crossregion-forward-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-crossregion-forward-role" }
}

resource "aws_iam_role_policy" "forward" {
  name = "${var.prefix}-crossregion-forward-policy"
  role = aws_iam_role.forward.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = aws_cloudwatch_event_bus.destination.arn
    }]
  })
}

# Rule on the SOURCE bus whose TARGET is the destination bus in the other region.
resource "aws_cloudwatch_event_rule" "forward" {
  name           = "${var.prefix}-forward-to-secondary"
  event_bus_name = aws_cloudwatch_event_bus.source.name
  description    = "Forward myapp.crossregion events to the ${data.aws_region.secondary.name} bus"
  event_pattern = jsonencode({
    source = ["myapp.crossregion"]
  })
}

resource "aws_cloudwatch_event_target" "forward" {
  rule           = aws_cloudwatch_event_rule.forward.name
  event_bus_name = aws_cloudwatch_event_bus.source.name
  target_id      = "to-secondary-bus"
  arn            = aws_cloudwatch_event_bus.destination.arn
  role_arn       = aws_iam_role.forward.arn
}
