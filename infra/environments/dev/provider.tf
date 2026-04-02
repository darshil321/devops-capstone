# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================
# A Terraform "provider" is a plugin that knows how to talk to a specific API.
# The AWS provider translates Terraform resource definitions into AWS API calls.
#
# Without a provider:
#   - Terraform has no idea what "aws_vpc" or "aws_s3_bucket" means
#   - The provider downloads the schema for every AWS resource type
#   - It handles auth, retries, pagination, and API versioning for you
#
# GCP equivalent: google provider (google_compute_network, google_storage_bucket)
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # ~> 5.0 means: >= 5.0.0 and < 6.0.0
      # This prevents a major version bump from breaking your infra silently.
      # In production, pin to a specific minor: ~> 5.31.0
    }
  }

  # -------------------------------------------------------------------------
  # REMOTE STATE BACKEND
  # -------------------------------------------------------------------------
  # WHY remote state:
  #   - Local state (terraform.tfstate) only exists on your machine
  #   - If a teammate runs terraform apply, they have no idea what you built
  #   - State lock (via DynamoDB) prevents two people applying at the same time
  #     → same problem as a DB migration running twice: data corruption
  #
  # GCP equivalent: gcs backend with a GCS bucket + Cloud Spanner for locking
  #
  # Key breakdown:
  #   - bucket: where the state file lives (S3 object)
  #   - key: the path inside the bucket (dev/terraform.tfstate)
  #   - dynamodb_table: table for state locking (prevents concurrent applies)
  #   - encrypt: enable server-side encryption at rest
  backend "s3" {
    bucket         = "devops-capstone-tfstate-890742569958"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devops-capstone-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  # WHY default_tags:
  # Every resource created by this provider will automatically get these tags.
  # In AWS, tags are how you: track costs by team/environment, write IAM
  # conditions, filter resources in the console, and build runbooks.
  # Not tagging is the #1 reason AWS bills become unreadable at scale.
  default_tags {
    tags = {
      Project     = "devops-capstone"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
