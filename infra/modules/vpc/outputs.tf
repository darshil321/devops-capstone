# =============================================================================
# VPC MODULE OUTPUTS
# =============================================================================
# Outputs expose values from this module to the parent config.
# The parent (infra/environments/dev/main.tf) will reference these
# to pass subnet IDs to the EKS module, security group IDs to ALB, etc.
#
# Without outputs, the parent config has no way to know what was created.
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (null if disabled)"
  value       = try(aws_nat_gateway.main[0].id, null)
}

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}
