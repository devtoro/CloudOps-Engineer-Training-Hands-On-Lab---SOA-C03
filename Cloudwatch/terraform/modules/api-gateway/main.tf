# -----------------------------------------------------------------------------
# API Gateway — REST API
#
# A minimal REST API fronting the Orders Lambda with:
#   - POST /orders → Lambda proxy integration
#   - API key required on all methods (x-api-key header)
#   - Usage plan with throttle/quota limits
#   - Stage-level CloudWatch metrics enabled
#   - Execution logging at INFO level
#
# CloudOps exam notes:
#
# 1. REST API vs HTTP API metrics:
#    REST API publishes Count, 4XXError, 5XXError, Latency, and
#    IntegrationLatency as separate metrics under AWS/ApiGateway.
#    HTTP API only gives you a subset.
#
# 2. Latency vs IntegrationLatency:
#    - Latency = total time from API GW receiving the request to returning
#      the response (includes integration + API GW overhead).
#    - IntegrationLatency = time spent in the backend (Lambda).
#    Your "slow" handler path (5s sleep) will inflate both, but the gap
#    between them is the API GW overhead.
#
# 3. The account-level CloudWatch role:
#    REST APIs need an account-wide IAM role so API Gateway can push logs
#    to CloudWatch. Without it, stage logging is silently ignored — no error,
#    just no logs. This is a classic gotcha. The role is set via
#    aws_api_gateway_account, which is a REGION-WIDE singleton resource.
#
# 4. API keys:
#    API keys are for IDENTIFICATION and THROTTLING, not authentication.
#    The exam tests this distinction. Keys are sent in the x-api-key header.
#    A key without a usage plan is useless — the plan binds the key to a
#    stage and optionally adds rate limits and quotas.
# -----------------------------------------------------------------------------

# --- Account-level CloudWatch Logs role (region-wide singleton) --------------

resource "aws_iam_role" "api_gw_cloudwatch" {
  name = "${var.prefix}-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = { Name = "${var.prefix}-apigw-cloudwatch-role" }
}

resource "aws_iam_role_policy_attachment" "api_gw_cloudwatch" {
  role       = aws_iam_role.api_gw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api_gw_cloudwatch.arn
}

# --- REST API ----------------------------------------------------------------

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.prefix}-api"
  description = "Order Processing Platform — CloudOps training lab"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.prefix}-api" }
}

# --- /orders resource --------------------------------------------------------

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "orders"
}

# --- POST method (API key required) ------------------------------------------

resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"

  # Require an API key. Callers must send it in the "x-api-key" header.
  # NOTE: an API key is identification + throttling, NOT authentication.
  api_key_required = true
}

# --- Lambda proxy integration ------------------------------------------------
# AWS_PROXY passes the entire request to Lambda and lets the handler
# control the HTTP status code. That's how your 400/500 paths surface
# as API Gateway 4XXError / 5XXError metrics.

resource "aws_api_gateway_integration" "post_orders" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_orders.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.lambda_invoke_arn
}

# --- Deployment --------------------------------------------------------------

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.post_orders.id,
      aws_api_gateway_integration.post_orders.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Stage with logging + metrics enabled ------------------------------------

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.environment

  # X-Ray active tracing — API Gateway starts the trace and becomes the first
  # node in the service map, then passes the trace header to the Lambda.
  xray_tracing_enabled = true

  depends_on = [aws_api_gateway_account.this]

  tags = { Name = "${var.prefix}-${var.environment}" }
}

# Enable detailed metrics and logging at stage level
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = true
  }
}

# --- API Key + Usage Plan ----------------------------------------------------
#
# Four things must line up for an API key to work:
#   1. api_key_required = true  on the method         (above)
#   2. aws_api_gateway_api_key  — the key itself       (below)
#   3. aws_api_gateway_usage_plan — binds key to stage  (below)
#   4. aws_api_gateway_usage_plan_key — links key→plan  (below)
#
# Without the usage plan, API Gateway returns 403 even with a valid key.

resource "aws_api_gateway_api_key" "this" {
  name    = "${var.prefix}-api-key"
  enabled = true
  value   = var.api_key_value

  tags = { Name = "${var.prefix}-api-key" }
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.prefix}-usage-plan"
  description = "Usage plan for CloudOps training lab"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  # Modest limits — useful for observing 429 throttle metrics later
  throttle_settings {
    burst_limit = 10
    rate_limit  = 5
  }

  quota_settings {
    limit  = 1000
    period = "DAY"
  }

  tags = { Name = "${var.prefix}-usage-plan" }
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

# --- Lambda permission -------------------------------------------------------

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}
