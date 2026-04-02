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

  project_name      = var.project_name
  environment       = var.environment
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true

  tags = {
    Environment = var.environment
  }
}
