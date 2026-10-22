# -----------------------------------------------------------------------------
# managed-instance module — outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "The SSM-managed EC2 instance id"
  value       = aws_instance.node.id
}

output "instance_role_name" {
  description = "Name of the instance IAM role (for attaching extra policies)"
  value       = aws_iam_role.instance.name
}
