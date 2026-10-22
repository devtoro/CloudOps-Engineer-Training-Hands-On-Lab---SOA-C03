# -----------------------------------------------------------------------------
# EventBridge — Custom bus + rule → Processor Lambda
#
# Using a custom bus (not default) because:
#   - Custom buses let you scope rules cleanly to your app
#   - The exam expects you to know the difference between the default bus
#     (which receives AWS service events) and custom buses (your events)
#   - It's easier to monitor in CloudWatch — you can filter by bus name
#
# Flow: orders handler → put_events(Source=orders.api, DetailType=OrderCreated)
#       → rule matches → target invokes Processor Lambda (async)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_bus" "this" {
  name = "${var.prefix}-bus"

  tags = { Name = "${var.prefix}-bus" }
}

resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "${var.prefix}-order-created"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  description    = "Routes OrderCreated events to the Processor Lambda"

  event_pattern = jsonencode({
    source      = ["orders.api"]
    detail-type = ["OrderCreated"]
  })

  tags = { Name = "${var.prefix}-order-created" }
}

resource "aws_cloudwatch_event_target" "processor" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "processor-lambda"
  arn            = var.processor_lambda_arn
}

# Allow EventBridge to invoke the Processor Lambda
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.processor_lambda_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_created.arn
}
