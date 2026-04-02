# =============================================================================
# INPUT VARIABLES
# =============================================================================
# Variables are how you parameterize Terraform configs.
# Think of them like function arguments — they let the same module work
# in dev, staging, and prod without copy-pasting code.
#
# Set values via:
#   - terraform.tfvars file (checked in, no secrets)
#   - terraform.tfvars.json
#   - TF_VAR_<name> environment variable (for secrets in CI)
#   - -var flag: terraform apply -var="environment=prod"
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "project_name" {
  description = "Project name — used in resource naming and tags"
  type        = string
  default     = "devops-capstone"
}
