# -----------------------------------------------------------------------------
# run-and-inventory — Run Command + Inventory, both as State Manager associations
#
# A State Manager ASSOCIATION = (SSM document) + (targets) + (schedule). It
# applies the document to the targets on a cadence, keeping them in a desired
# state. Both Run Command tasks and Inventory collection are expressed this way
# when you want them to recur.
#
#   Run Command  → run scripts/commands on nodes. Ad-hoc via `aws ssm
#                  send-command`, or recurring via an association (here).
#   Inventory    → collect metadata (installed apps, patches, network config,
#                  Windows updates, custom inventory) via AWS-GatherSoftwareInventory.
#
# CloudOps exam notes:
#   - Run Command needs NO inbound ports / SSH — agent dials out (same model as
#     Session Manager). Target by instance id, tags, or resource groups.
#   - Inventory data is queryable in the console and via SSM; combine with
#     Resource Data Sync to aggregate inventory across accounts/regions to S3.
#   - Associations show compliance (did the document apply successfully?).
# -----------------------------------------------------------------------------

# =============================================================================
# Run Command association — run a shell script on a schedule
# =============================================================================
resource "aws_ssm_association" "run_command" {
  association_name = "${var.prefix}-run-command"
  name             = "AWS-RunShellScript" # the AWS-managed command document

  # Run every 30 minutes (cron is UTC). Also runs once at association create.
  schedule_expression = "rate(30 minutes)"

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }

  parameters = {
    commands = "echo \"[$(date -u)] hello from Run Command on $(hostname)\"; uptime"
  }

  # Keep a cap on concurrent/erroring targets (good practice at fleet scale).
  max_concurrency = "1"
  max_errors      = "1"
}

# =============================================================================
# Inventory association — collect software/patch/network/config metadata
# =============================================================================
resource "aws_ssm_association" "inventory" {
  association_name = "${var.prefix}-inventory"
  name             = "AWS-GatherSoftwareInventory"

  # Inventory is collected on a schedule (min 30 min).
  schedule_expression = "rate(30 minutes)"

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }

  # What to gather. "Enabled"/"Disabled" per inventory type.
  parameters = {
    applications                = "Enabled"
    awsComponents               = "Enabled"
    networkConfig               = "Enabled"
    instanceDetailedInformation = "Enabled"
    services                    = "Enabled"
    windowsUpdates              = "Enabled"
  }
}

# =============================================================================
# OPTIONAL: Resource Data Sync (commented) — aggregate inventory from all
# managed nodes (and across accounts/regions) into a central S3 bucket for
# querying with Athena/QuickSight.
#
# resource "aws_ssm_resource_data_sync" "inventory" {
#   name = "${var.prefix}-inventory-sync"
#   s3_destination {
#     bucket_name = "<central-inventory-bucket>"
#     region      = "eu-central-1"
#     sync_format = "JsonSerDe"
#   }
# }
# =============================================================================
