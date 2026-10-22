# -----------------------------------------------------------------------------
# managed-instance — the SSM-managed node that every other feature acts on
#
# What makes an EC2 instance an SSM "managed node":
#   1. SSM Agent running   (pre-installed on Amazon Linux 2023)
#   2. Instance profile with AmazonSSMManagedInstanceCore
#   3. Outbound 443 to the SSM endpoints (egress-only SG here; use VPC
#      endpoints in a locked-down private subnet)
#
# Note the EGRESS-ONLY security group: NO inbound rules. Session Manager, Run
# Command, Patch, and Inventory all work because the AGENT DIALS OUT — nothing
# listens inbound. This is the whole security story of SSM-managed access.
#
# EC2 managed node id = "i-..."; a HYBRID-activated node id = "mi-..." (see the
# commented hybrid activation block at the bottom).
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_vpc" "default" {
  default = true
}

# --- Instance role + profile -------------------------------------------------
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

# The core policy that makes the agent able to register + be managed, and
# enables Session Manager, Run Command, Patch, Inventory.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.prefix}-instance-profile"
  role = aws_iam_role.instance.name
}

# --- Egress-only security group (NO inbound) ---------------------------------
resource "aws_security_group" "instance" {
  name        = "${var.prefix}-node-sg"
  description = "SSM managed node - egress only (no SSH/RDP inbound)"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Outbound HTTPS for the SSM agent (and general egress)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-node-sg" }
}

# --- The managed instance ----------------------------------------------------
resource "aws_instance" "node" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  vpc_security_group_ids = [aws_security_group.instance.id]

  tags = {
    Name = "${var.prefix}-node"
    # Patch Manager groups instances by this exact tag KEY ("Patch Group").
    "Patch Group" = var.patch_group
  }
}

# =============================================================================
# HYBRID ACTIVATION (reference — manage on-prem / non-EC2 nodes)
#
# Needs a real external machine to register, so it's commented. The shape:
#
#   1. A SERVICE role the hybrid agent assumes (trust: ssm.amazonaws.com):
#
# resource "aws_iam_role" "hybrid" {
#   name = "${var.prefix}-hybrid-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow", Principal = { Service = "ssm.amazonaws.com" },
#       Action = "sts:AssumeRole"
#     }]
#   })
# }
# resource "aws_iam_role_policy_attachment" "hybrid_core" {
#   role       = aws_iam_role.hybrid.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }
#
#   2. An ACTIVATION — produces an Activation Code + Activation ID:
#
# resource "aws_ssm_activation" "hybrid" {
#   name               = "${var.prefix}-hybrid"
#   iam_role           = aws_iam_role.hybrid.name
#   registration_limit = 5
#   depends_on         = [aws_iam_role_policy_attachment.hybrid_core]
# }
#
#   3. ON THE ON-PREM MACHINE, install the agent and register with the code/id:
#        sudo amazon-ssm-agent -register -code "<ActivationCode>" \
#          -id "<ActivationId>" -region "eu-central-1"
#
# The node then appears as a managed node with an "mi-..." id (vs "i-..." for
# EC2) and supports Session Manager / Run Command / Patch / Inventory just like
# an EC2 instance.
#
# Exam angle: hybrid activation extends SSM to on-prem servers, VMs, and other
# clouds — one control plane for all your nodes. EC2 uses the instance profile;
# hybrid uses an activation + service role, and gets an "mi-" id.
# =============================================================================
