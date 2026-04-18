# =============================================================================
# EKS MODULE OUTPUTS
# =============================================================================

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate for cluster CA (needed for kubectl)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster control plane"
  value       = aws_security_group.cluster.id
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_status" {
  description = "Status of the node group (CREATING, ACTIVE, DELETING, FAILED, UPDATING, PENDING)"
  value       = aws_eks_node_group.main.status
}
