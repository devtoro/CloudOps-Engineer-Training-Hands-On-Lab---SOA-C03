# =============================================================================
# Root outputs — uncomment as modules are added.
# =============================================================================

output "instance_id" {
  description = "EC2 instance that gets auto-healed"
  value       = module.demo_target.instance_id
}
#
output "autoheal_rule_name" {
  description = "EventBridge rule that triggers EC2 auto-heal"
  value       = module.autoheal_ssm.rule_name
}

output "autoheal_dlq_url" {
  description = "DLQ URL for undeliverable auto-heal target invocations"
  value       = module.autoheal_ssm.dlq_url
}
#
output "secondary_bus_name" {
  description = "Destination bus (eu-west-1) for cross-Region forwarding"
  value       = module.cross_region.secondary_bus_name
}
