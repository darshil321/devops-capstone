# =============================================================================
# MAIN ENTRYPOINT — DEV ENVIRONMENT
# =============================================================================
# This file instantiates modules from infra/modules/ with dev-specific values.
#
# Module instantiation syntax:
#   module "<local_name>" {
#     source = "../../modules/<module_name>"
#     var1 = value1
#     var2 = value2
#   }
#
# The <local_name> becomes the prefix for references:
#   - module.vpc.vpc_id references the vpc_id output from the vpc module
#   - module.vpc.public_subnet_ids references the public subnet list
#
# This indirection (modules → environments) allows the same module code to
# create different infrastructure in dev vs prod by changing the input variables.
# =============================================================================

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true

  tags = {
    Environment = var.environment
  }
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment

  tags = {
    Environment = var.environment
  }
}

module "ecr" {
  source = "../../modules/ecr"

  project_name           = var.project_name
  environment            = var.environment
  image_tag_mutability   = "MUTABLE"
  image_retention_count  = 10

  tags = {
    Environment = var.environment
  }
}

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = "10.0.0.0/16"

  tags = {
    Environment = var.environment
  }
}

module "eks" {
  source = "../../modules/eks"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  node_security_group_id    = module.security.node_security_group_id
  eks_node_role_arn         = module.iam.eks_node_role_arn
  node_instance_type        = "t3.medium"
  desired_node_count        = 2
  min_node_count            = 1
  max_node_count            = 3
  kubernetes_version        = "1.29"

  tags = {
    Environment = var.environment
  }

  depends_on = [
    module.vpc,
    module.iam,
    module.security,
  ]
}
