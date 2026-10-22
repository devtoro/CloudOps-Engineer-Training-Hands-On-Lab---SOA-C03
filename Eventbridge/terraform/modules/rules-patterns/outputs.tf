# -----------------------------------------------------------------------------
# rules-patterns module — outputs
# -----------------------------------------------------------------------------

output "custom_bus_name" {
  description = "Name of the custom demo event bus"
  value       = aws_cloudwatch_event_bus.demo.name
}

output "custom_bus_arn" {
  description = "ARN of the custom demo event bus"
  value       = aws_cloudwatch_event_bus.demo.arn
}

output "rule_names" {
  description = "Names of the pattern-demo rules on the custom bus"
  value       = [for r in aws_cloudwatch_event_rule.pattern : r.name]
}
