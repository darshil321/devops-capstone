# =============================================================================
# EKS MODULE INPUT VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for cluster naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for worker nodes"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID for worker nodes"
  type        = string
}

variable "eks_node_role_arn" {
  description = "ARN of the IAM role for EKS nodes"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^t3\\.|^t4g\\.|^m5\\.|^m6i\\.", var.node_instance_type))
    error_message = "node_instance_type must be a valid instance type (t3.*, t4g.*, m5.*, m6i.*)"
  }
}

variable "desired_node_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.desired_node_count >= 1 && var.desired_node_count <= 10
    error_message = "desired_node_count must be between 1 and 10"
  }
}

variable "min_node_count" {
  description = "Minimum number of worker nodes (for scaling)"
  type        = number
  default     = 1

  validation {
    condition     = var.min_node_count >= 1
    error_message = "min_node_count must be at least 1"
  }
}

variable "max_node_count" {
  description = "Maximum number of worker nodes (for scaling)"
  type        = number
  default     = 5

  validation {
    condition     = var.max_node_count >= var.desired_node_count
    error_message = "max_node_count must be >= desired_node_count"
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^1\\.(2[8-9]|[3-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be 1.28 or newer"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
