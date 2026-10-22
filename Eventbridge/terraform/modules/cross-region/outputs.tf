# -----------------------------------------------------------------------------
# cross-region module — outputs
# -----------------------------------------------------------------------------

output "source_bus_name" {
  description = "Source bus (primary region) that forwards events"
  value       = aws_cloudwatch_event_bus.source.name
}

output "secondary_bus_name" {
  description = "Destination bus (secondary region) that receives forwarded events"
  value       = aws_cloudwatch_event_bus.destination.name
}

output "destination_log_group" {
  description = "CloudWatch Logs group in the secondary region where forwarded events land"
  value       = aws_cloudwatch_log_group.destination.name
}
