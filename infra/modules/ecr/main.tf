# =============================================================================
# ECR MODULE
# =============================================================================
# Elastic Container Registry (ECR) is AWS's private Docker registry.
# You push images here, and EKS pulls from here.
#
# Architecture:
#   - 1 ECR repository per application
#   - Lifecycle policy to auto-delete old images (keep only last N)
#   - Encryption at rest (enabled by default)
#   - Pull-through cache (optional, for caching public images locally)
#
# Cost: ~$0.07 per GB/month storage
# For 260MB NestJS image: ~$0.02/month per image * 10 retained = $0.20/month
# =============================================================================

# =============================================================================
# ECR REPOSITORY
# =============================================================================
# Private registry where Docker images are stored.
# Only authenticated users/roles can push/pull.
#
# WHY ECR over Docker Hub:
#   - Integrated with EKS (no need to authenticate separately)
#   - Lives in your AWS account (private by default)
#   - Can write IAM policies to control access
#   - Cheaper than Docker Hub Pro
# =============================================================================

resource "aws_ecr_repository" "main" {
  name                 = "${var.project_name}-${var.environment}"
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push (optional, costs extra)
  image_scanning_configuration {
    scan_on_push = false
  }

  # Encryption at rest (enabled by default with AWS managed key)
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}"
    }
  )
}

# =============================================================================
# ECR LIFECYCLE POLICY
# =============================================================================
# Automatically delete old images to save storage costs.
#
# WHY: Without this policy, ECR keeps every image forever.
# A week of daily builds = 7 images. A month = 30 images.
# Each image is 260MB, so 30 images = 7.8GB = $0.55/month.
#
# This policy keeps only the last 10 images, auto-deletes older ones.
# Cost savings: Keep 10 * 260MB = 2.6GB = $0.18/month (vs $0.55)
# =============================================================================

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last N images, delete older ones"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# ECR REPOSITORY POLICY (Optional)
# =============================================================================
# Controls who can push/pull images.
# By default, only authenticated IAM users in this account can access.
# This is secure-by-default — no public images without explicit permission.
#
# In Phase 4, we'll add a policy that allows the Jenkins pipeline to push.
# In Phase 3, only your laptop needs to push (and you have AWS CLI credentials).
# =============================================================================

# No explicit policy needed for Phase 3 — your IAM user has full access
# In Phase 4, we'll add:
#   resource "aws_ecr_repository_policy" "jenkins" { ... }
