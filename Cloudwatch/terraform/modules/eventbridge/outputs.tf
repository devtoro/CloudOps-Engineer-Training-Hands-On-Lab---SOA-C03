# -----------------------------------------------------------------------------
# EventBridge module — outputs
# The orders Lambda needs bus_name + bus_arn to emit events to it.
# -----------------------------------------------------------------------------

output "bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.this.name
}

output "bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.this.arn
}
