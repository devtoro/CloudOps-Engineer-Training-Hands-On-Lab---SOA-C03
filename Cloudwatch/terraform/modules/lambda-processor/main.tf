# -----------------------------------------------------------------------------
# Lambda: Processor
#
# Invoked ASYNCHRONOUSLY by EventBridge. Only needs CloudWatch Logs
# permissions — it reads the event payload and logs; it doesn't touch
# DynamoDB or EventBridge itself.
#
# CloudOps exam note:
#   Async invocation (EventBridge, S3 events, SNS) retries failures twice
#   by default. We leave the default here (maximum_retry_attempts not set),
#   so a failing processor shows up as 3 Invocations + 3 Errors per event.
# -----------------------------------------------------------------------------

# --- Vendor Python dependencies (aws-xray-sdk) into the source dir -----------
resource "null_resource" "processor_deps" {
  triggers = {
    requirements = filemd5("${var.source_dir}/requirements.txt")
    handler      = filemd5("${var.source_dir}/handler.py")
  }

  provisioner "local-exec" {
    command = "pip install -r ${var.source_dir}/requirements.txt -t ${var.source_dir} --upgrade"
  }
}

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/processor.zip"

  depends_on = [null_resource.processor_deps]
}

resource "aws_iam_role" "processor_lambda" {
  name = "${var.prefix}-processor-lambda-role"

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

  tags = { Name = "${var.prefix}-processor-lambda-role" }
}

resource "aws_iam_role_policy" "processor_logs" {
  name = "${var.prefix}-processor-logs"
  role = aws_iam_role.processor_lambda.id

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

# X-Ray permissions — lets the processor upload trace segments.
resource "aws_iam_role_policy_attachment" "processor_xray" {
  role       = aws_iam_role.processor_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.prefix}-processor"
  role          = aws_iam_role.processor_lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  memory_size   = var.memory_size
  timeout       = var.timeout

  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256

  # Active tracing — emit segments to X-Ray.
  tracing_config {
    mode = "Active"
  }

  tags = { Name = "${var.prefix}-processor" }
}
