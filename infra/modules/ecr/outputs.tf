# =============================================================================
# ECR MODULE OUTPUTS
# =============================================================================

output "repository_url" {
  description = "ECR repository URL (e.g., 890742569958.dkr.ecr.us-east-1.amazonaws.com/devops-capstone-dev)"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

output "registry_id" {
  description = "AWS account ID (needed for docker login)"
  value       = aws_ecr_repository.main.registry_id
}
