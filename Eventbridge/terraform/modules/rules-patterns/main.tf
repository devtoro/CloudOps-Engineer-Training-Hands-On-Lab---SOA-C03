# -----------------------------------------------------------------------------
# rules-patterns — EventBridge event-pattern matching, by example
#
# A custom bus plus several rules, each showing a different matching construct.
# Every rule routes to the log-target Lambda, so you can PUT a test event and
# then read the Lambda's logs to confirm which rule(s) matched.
#
# Event-pattern matching rules (CloudOps exam core):
#   - A pattern is JSON that mirrors the event's shape.
#   - A field matches if the event's value is in the pattern's ARRAY of options.
#   - Omitting a field means "don't care" about it.
#   - Content filters add operators: prefix, suffix, anything-but, numeric,
#     exists, cidr, equals-ignore-case, and $or.
#   - ALL specified fields must match (implicit AND across fields).
# -----------------------------------------------------------------------------

# --- Custom bus --------------------------------------------------------------
resource "aws_cloudwatch_event_bus" "demo" {
  name = "${var.prefix}-demo-bus"
  tags = { Name = "${var.prefix}-demo-bus" }
}

# --- The pattern catalogue ---------------------------------------------------
# Each entry is one rule. The value is the event_pattern JSON.
locals {
  patterns = {
    # 1. EXACT MATCH — source must equal exactly "myapp.orders".
    exact = {
      source = ["myapp.orders"]
    }

    # 2. PREFIX — detail.region begins with "eu-".
    prefix = {
      source = ["myapp.orders"]
      detail = {
        region = [{ prefix = "eu-" }]
      }
    }

    # 3. ANYTHING-BUT — detail.status is anything except "ok".
    anything_but = {
      source = ["myapp.health"]
      detail = {
        status = [{ "anything-but" = ["ok"] }]
      }
    }

    # 4. NUMERIC — detail.amount strictly greater than 100.
    numeric = {
      source = ["myapp.orders"]
      detail = {
        amount = [{ numeric = [">", 100] }]
      }
    }

    # 5. EXISTS — detail.errorCode is present (regardless of value).
    exists = {
      source = ["myapp.orders"]
      detail = {
        errorCode = [{ exists = true }]
      }
    }
  }
}

# --- One rule per pattern ----------------------------------------------------
resource "aws_cloudwatch_event_rule" "pattern" {
  for_each = local.patterns

  name           = "${var.prefix}-${each.key}"
  event_bus_name = aws_cloudwatch_event_bus.demo.name
  description    = "Pattern demo: ${each.key}"
  event_pattern  = jsonencode(each.value)

  tags = { Name = "${var.prefix}-${each.key}" }
}

# --- Target every rule at the log-target Lambda ------------------------------
resource "aws_cloudwatch_event_target" "pattern" {
  for_each = aws_cloudwatch_event_rule.pattern

  rule           = each.value.name
  event_bus_name = aws_cloudwatch_event_bus.demo.name
  target_id      = "log-target"
  arn            = var.log_target_arn
}

# --- Allow EventBridge to invoke the Lambda for each rule --------------------
resource "aws_lambda_permission" "pattern" {
  for_each = aws_cloudwatch_event_rule.pattern

  statement_id  = "AllowEB-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = var.log_target_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.arn
}

# =============================================================================
# A rule matching a REAL AWS service event (on the DEFAULT bus).
#
# AWS service events are delivered to the DEFAULT bus. This rule matches EC2
# instance state-change notifications — the kind of "respond to AWS service
# changes" event your objectives call out. It also routes to the log-target so
# you can see the shape of a genuine AWS event vs. your custom ones.
# =============================================================================
resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  name        = "${var.prefix}-ec2-state-change"
  description = "Matches EC2 instance state-change notifications (AWS service event)"

  # Note: no event_bus_name → defaults to the account's default bus, which is
  # where AWS service events land.
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["stopped", "stopping", "terminated"]
    }
  })

  tags = { Name = "${var.prefix}-ec2-state-change" }
}

resource "aws_cloudwatch_event_target" "ec2_state_change" {
  rule      = aws_cloudwatch_event_rule.ec2_state_change.name
  target_id = "log-target"
  arn       = var.log_target_arn
}

resource "aws_lambda_permission" "ec2_state_change" {
  statement_id  = "AllowEB-ec2-state-change"
  action        = "lambda:InvokeFunction"
  function_name = var.log_target_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_state_change.arn
}
