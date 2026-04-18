# =============================================================================
# ECR MODULE INPUT VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for repository naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE"
  }
}

variable "image_retention_count" {
  description = "Number of images to retain (older images are deleted)"
  type        = number
  default     = 10

  validation {
    condition     = var.image_retention_count > 0 && var.image_retention_count <= 100
    error_message = "image_retention_count must be between 1 and 100"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
