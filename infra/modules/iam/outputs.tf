# =============================================================================
# IAM MODULE OUTPUTS
# =============================================================================

output "ec2_tfstate_reader_role_arn" {
  description = "ARN of the EC2 role that can read Terraform state"
  value       = aws_iam_role.ec2_tfstate_reader.arn
}

output "ec2_tfstate_reader_instance_profile_arn" {
  description = "ARN of the instance profile (for attaching to EC2)"
  value       = aws_iam_instance_profile.ec2_tfstate_reader.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node role"
  value       = aws_iam_role.eks_node_role.arn
}

output "eks_node_instance_profile_arn" {
  description = "ARN of the EKS node instance profile"
  value       = aws_iam_instance_profile.eks_node_profile.arn
}

output "eks_pod_execution_role_arn" {
  description = "ARN of the EKS pod execution role (IRSA)"
  value       = aws_iam_role.eks_pod_execution_role.arn
}
