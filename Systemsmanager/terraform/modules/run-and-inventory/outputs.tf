# -----------------------------------------------------------------------------
# run-and-inventory module — outputs
# -----------------------------------------------------------------------------

output "run_command_association_id" {
  description = "Association id for the scheduled Run Command"
  value       = aws_ssm_association.run_command.association_id
}

output "inventory_association_id" {
  description = "Association id for the Inventory collection"
  value       = aws_ssm_association.inventory.association_id
}
