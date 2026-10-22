# -----------------------------------------------------------------------------
# demo-target — the things EventBridge rules will act on / route to
#
#   - EC2 instance        → the resource we auto-heal (restart via SSM)
#   - Log-target Lambda   → a visible target: logs whatever event it receives,
#                           so you can confirm which rule matched
#   - SNS topic           → an alternate target (no subscription by default)
#
# The EC2 instance gets the SSM core managed policy so the AWS-RestartEC2Instance
# automation (and general SSM) can operate on it.
# -----------------------------------------------------------------------------

# --- Latest Amazon Linux 2023 AMI via SSM public parameter -------------------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- Default VPC (lab convenience) -------------------------------------------
data "aws_vpc" "default" {
  default = true
}

# --- Instance role + profile (SSM-managed) -----------------------------------
resource "aws_iam_role" "instance" {
  name = "${var.prefix}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-instance-role" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.prefix}-instance-profile"
  role = aws_iam_role.instance.name
}

# --- Minimal security group (no inbound; SSM uses outbound only) -------------
resource "aws_security_group" "instance" {
  name        = "${var.prefix}-instance-sg"
  description = "Auto-heal demo target - egress only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "All outbound (SSM agent needs HTTPS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-instance-sg" }
}

# --- The EC2 instance --------------------------------------------------------
resource "aws_instance" "target" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  vpc_security_group_ids = [aws_security_group.instance.id]

  tags = {
    Name     = "${var.prefix}-target"
    AutoHeal = "true" # a tag our EventBridge pattern can match on
  }
}

# --- SNS topic (alternate rule target) ---------------------------------------
resource "aws_sns_topic" "notifications" {
  name = "${var.prefix}-notifications"
}

# --- Log-target Lambda -------------------------------------------------------
data "archive_file" "log_target" {
  type        = "zip"
  source_dir  = var.log_target_source_dir
  output_path = "${path.module}/log_target.zip"
}

resource "aws_iam_role" "log_target" {
  name = "${var.prefix}-log-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-log-target-role" }
}

resource "aws_iam_role_policy" "log_target_logs" {
  name = "${var.prefix}-log-target-logs"
  role = aws_iam_role.log_target.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_lambda_function" "log_target" {
  function_name = "${var.prefix}-log-target"
  role          = aws_iam_role.log_target.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.log_target.output_path
  source_code_hash = data.archive_file.log_target.output_base64sha256

  tags = { Name = "${var.prefix}-log-target" }
}
