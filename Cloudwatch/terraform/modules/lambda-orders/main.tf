# -----------------------------------------------------------------------------
# Lambda: Orders
#
# Sits behind API Gateway. Writes to DynamoDB, emits to EventBridge.
#
# IAM follows least-privilege:
#   - CloudWatch Logs: CreateLogGroup, CreateLogStream, PutLogEvents
#   - DynamoDB: PutItem on the orders table only
#   - EventBridge: PutEvents on the target bus only
#
# CloudOps exam note:
#   Lambda MUST have logs:CreateLogGroup + logs:CreateLogStream +
#   logs:PutLogEvents permissions, or you get zero CloudWatch Logs.
#   These are NOT included in AWSLambdaBasicExecutionRole by magic —
#   that managed policy just happens to grant them. If you write a
#   custom policy and forget them, you'll see Invocations metrics
#   but no logs. That's a real exam scenario.
# -----------------------------------------------------------------------------

# --- Vendor Python dependencies (aws-xray-sdk) into the source dir -----------
# The X-Ray SDK is NOT in the Lambda runtime by default, so we pip install it
# alongside the handler before zipping. Re-runs when requirements.txt changes.
resource "null_resource" "orders_deps" {
  triggers = {
    requirements = filemd5("${var.source_dir}/requirements.txt")
    handler      = filemd5("${var.source_dir}/handler.py")
  }

  provisioner "local-exec" {
    command = "pip install -r ${var.source_dir}/requirements.txt -t ${var.source_dir} --upgrade"
  }
}

# --- Package the handler code (+ vendored deps) ------------------------------

data "archive_file" "orders" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/orders.zip"

  depends_on = [null_resource.orders_deps]
}

# --- IAM role ----------------------------------------------------------------

resource "aws_iam_role" "orders_lambda" {
  name = "${var.prefix}-orders-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = { Name = "${var.prefix}-orders-lambda-role" }
}

# CloudWatch Logs permissions
resource "aws_iam_role_policy" "orders_logs" {
  name = "${var.prefix}-orders-logs"
  role = aws_iam_role.orders_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# DynamoDB permissions — PutItem only, scoped to the orders table
resource "aws_iam_role_policy" "orders_dynamodb" {
  name = "${var.prefix}-orders-dynamodb"
  role = aws_iam_role.orders_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = var.dynamodb_table_arn
    }]
  })
}

# EventBridge permissions — PutEvents only, scoped to the bus
resource "aws_iam_role_policy" "orders_eventbridge" {
  name = "${var.prefix}-orders-eventbridge"
  role = aws_iam_role.orders_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = var.event_bus_arn != "" ? var.event_bus_arn : "*"
    }]
  })
}

# X-Ray permissions — lets the function upload trace segments.
# The AWS-managed policy grants exactly:
#   xray:PutTraceSegments, xray:PutTelemetryRecords,
#   xray:GetSamplingRules, xray:GetSamplingTargets, xray:GetSamplingStatisticSummaries
# Exam note: with Active tracing but NO X-Ray IAM permissions, you get silent
# gaps — the service map shows the node but segments fail to upload.
resource "aws_iam_role_policy_attachment" "orders_xray" {
  role       = aws_iam_role.orders_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# --- Lambda function ---------------------------------------------------------

resource "aws_lambda_function" "orders" {
  function_name = "${var.prefix}-orders"
  role          = aws_iam_role.orders_lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  memory_size   = var.memory_size
  timeout       = var.timeout

  filename         = data.archive_file.orders.output_path
  source_code_hash = data.archive_file.orders.output_base64sha256

  # Active tracing — Lambda samples invocations and emits segments to X-Ray.
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ORDERS_TABLE   = var.dynamodb_table_name
      EVENT_BUS_NAME = var.event_bus_name
    }
  }

  tags = { Name = "${var.prefix}-orders" }
}
