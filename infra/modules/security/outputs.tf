# =============================================================================
# SECURITY MODULE OUTPUTS
# =============================================================================

output "node_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.node.id
}

output "pod_security_group_id" {
  description = "Security group ID for pods (future use)"
  value       = aws_security_group.pod.id
}
