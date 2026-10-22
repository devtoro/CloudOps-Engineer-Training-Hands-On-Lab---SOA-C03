# -----------------------------------------------------------------------------
# patch-manager — automated patch SCANNING (read-only, no reboots)
#
# Pieces of Patch Manager:
#   1. Patch BASELINE   — rules for which patches are "approved" (by severity,
#      classification, auto-approval delay). Each OS has an AWS default baseline;
#      here we define a CUSTOM one.
#   2. Patch GROUP      — instances are grouped by the "Patch Group" TAG. A patch
#      group is registered to exactly one baseline per OS.
#   3. MAINTENANCE WINDOW — a schedule + targets + task that runs
#      AWS-RunPatchBaseline against the group.
#
# Operation = "Scan" → reports compliance (missing/installed patches) WITHOUT
# installing anything or rebooting. Switch to "Install" to actually patch (shown
# commented) — that can reboot, so we keep the lab scan-only.
#
# CloudOps exam notes:
#   - Instances are matched to a baseline via the "Patch Group" tag.
#   - AWS-RunPatchBaseline is the document that scans/installs; Operation
#     parameter = Scan | Install.
#   - Patch compliance surfaces in SSM Compliance (and can flow to Security Hub).
# -----------------------------------------------------------------------------

# =============================================================================
# 1. Custom patch baseline (Amazon Linux 2023)
# =============================================================================
resource "aws_ssm_patch_baseline" "this" {
  name             = "${var.prefix}-al2023-baseline"
  description      = "Custom AL2023 baseline - approve Security/Bugfix after 7 days"
  operating_system = "AMAZON_LINUX_2023"

  approval_rule {
    approve_after_days  = 7
    compliance_level    = "HIGH"
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = { Name = "${var.prefix}-al2023-baseline" }
}

# =============================================================================
# 2. Register the patch GROUP (tag value) to this baseline
# =============================================================================
resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.this.id
  patch_group = var.patch_group
}

# =============================================================================
# 3. Maintenance window: schedule → target the patch group → run patch scan
# =============================================================================
resource "aws_ssm_maintenance_window" "this" {
  name                       = "${var.prefix}-patch-window"
  schedule                   = var.maintenance_window_schedule
  duration                   = 2 # hours
  cutoff                     = 1 # stop starting new tasks 1h before end
  allow_unassociated_targets = false

  tags = { Name = "${var.prefix}-patch-window" }
}

# Target = instances carrying the Patch Group tag.
resource "aws_ssm_maintenance_window_target" "this" {
  window_id     = aws_ssm_maintenance_window.this.id
  name          = "${var.prefix}-patch-targets"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Patch Group"
    values = [var.patch_group]
  }
}

# Role the maintenance window uses to run tasks on your behalf.
resource "aws_iam_role" "mw" {
  name = "${var.prefix}-mw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-mw-role" }
}

resource "aws_iam_role_policy_attachment" "mw" {
  role       = aws_iam_role.mw.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

# Task: run AWS-RunPatchBaseline in SCAN mode against the target group.
resource "aws_ssm_maintenance_window_task" "patch_scan" {
  window_id        = aws_ssm_maintenance_window.this.id
  name             = "${var.prefix}-patch-scan"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.mw.arn
  max_concurrency  = "1"
  max_errors       = "1"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Scan"] # read-only. Use ["Install"] to actually patch (reboots!).
      }
    }
  }
}

# =============================================================================
# INSTALL variant (commented) — same task with Operation = Install.
# Installing can REBOOT the instance; keep the lab scan-only by default.
#
#   parameter {
#     name   = "Operation"
#     values = ["Install"]
#   }
#   parameter {
#     name   = "RebootOption"
#     values = ["RebootIfNeeded"]   # or "NoReboot"
#   }
# =============================================================================
