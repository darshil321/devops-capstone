# Terraform Getting Started Guide

## What It Is

Terraform is **infrastructure as code** — you write configuration files that describe AWS resources, and Terraform figures out how to create them.

**Key insight:** You declare desired state, Terraform makes reality match desired state.

## Three Essential Files

### 1. `provider.tf` — Terraform Configuration

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
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
  default_tags {
    tags = {
      Project     = "devops-capstone"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

**What this does:**
- **terraform block:** Version constraints, provider source, remote state backend
- **provider block:** AWS region, default tags applied to all resources

**backend "s3":** Stores state in S3 (not on your laptop). DynamoDB table provides locking (prevents two applies simultaneously).

### 2. `variables.tf` — Input Parameters

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod"
  }
}
```

**What this does:**
- Declares what inputs exist
- Sets defaults
- Validates inputs (fail fast before any API calls)

**Set values via:**
- `terraform apply -var="environment=prod"`
- `export TF_VAR_environment=prod`
- `terraform.tfvars` file
- Command-line prompt (if no default and no var provided)

### 3. `main.tf` — Resource Definitions

```hcl
module "vpc" {
  source = "../../modules/vpc"
  
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true
}

resource "aws_s3_bucket" "example" {
  bucket = "my-bucket-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "my-bucket"
  }
}
```

**What this does:**
- Calls modules (reusable infrastructure)
- Defines resources (EC2, S3, VPC, etc.)

## Core Workflow

### Step 1: `terraform init`

```bash
terraform init
```

**What it does:**
1. Downloads the AWS provider plugin (~100MB)
2. Creates `.terraform/` directory (local cache)
3. Creates `.terraform.lock.hcl` (pins provider version)
4. Connects to remote state backend (S3)

**What to expect:**
```
Initializing the backend...
Successfully configured the backend "s3"!
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
Terraform has been successfully initialized!
```

### Step 2: `terraform plan`

```bash
terraform plan
```

**What it does:**
1. Reads `.tf` files
2. Validates syntax
3. Reads current state from S3
4. Compares desired (code) vs actual (AWS)
5. Shows what will change (without making changes)

**Output format:**
```
Terraform will perform the following actions:

  # aws_vpc.main will be created
  + resource "aws_vpc" "main" {
      + cidr_block           = "10.0.0.0/16"
      + enable_dns_hostnames = true
      + ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

**Symbols:**
- `+` create
- `~` update (in-place)
- `-/+` destroy and recreate
- `-` destroy

### Step 3: `terraform apply`

```bash
terraform apply
```

**What it does:**
1. Runs the same plan
2. Prompts for confirmation
3. Acquires state lock (DynamoDB)
4. Makes API calls to AWS
5. Updates state file in S3
6. Releases state lock

**Output:**
```
Do you want to perform these actions?
  Only 'yes' will be accepted to approve.

  Enter a value: yes

aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 16s [id=vpc-0c0703653eeac7d91]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### Step 4: `terraform destroy` (to clean up)

```bash
terraform destroy
```

**What it does:**
1. Plans deletion of all resources
2. Prompts for confirmation
3. Deletes resources in AWS
4. Updates state file

**Use case:** Dev environments you don't need anymore, testing VPCs, expensive resources (NAT Gateway).

## State File

**State file** = single source of truth about what Terraform has created.

**Example:**
```json
{
  "resources": [
    {
      "type": "aws_vpc",
      "name": "main",
      "instances": [
        {
          "attributes": {
            "id": "vpc-0c0703653eeac7d91",
            "cidr_block": "10.0.0.0/16",
            "enable_dns_hostnames": true
          }
        }
      ]
    }
  ]
}
```

**Why it matters:**
- Terraform reads it to know what was created
- If state says VPC exists but AWS has it deleted, `terraform plan` detects drift
- If state is corrupted, you can't manage infrastructure (this is why S3 versioning exists)

**Where it lives:**
- **Local:** `terraform.tfstate` (dangerous — not backed up, only on one laptop)
- **Remote (S3):** Safe, backed up, shared across team

**Never commit local state to git** — it contains resource IDs and sometimes secrets.

## Modules

A module is reusable Terraform code.

```
infra/
├── modules/
│   ├── vpc/
│   │   ├── main.tf        # Resource definitions
│   │   ├── variables.tf    # Inputs
│   │   └── outputs.tf      # Outputs
│   ├── iam/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
└── environments/
    ├── dev/
    │   ├── main.tf        # Call modules with dev values
    │   ├── variables.tf
    │   └── provider.tf
    └── prod/
        ├── main.tf        # Call modules with prod values
        ├── variables.tf
        └── provider.tf
```

**How it works:**

`infra/modules/vpc/main.tf`:
```hcl
variable "vpc_cidr" { type = string }

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

output "vpc_id" {
  value = aws_vpc.main.id
}
```

`infra/environments/dev/main.tf`:
```hcl
module "vpc" {
  source = "../../modules/vpc"
  vpc_cidr = "10.0.0.0/16"
}

module "iam" {
  source = "../../modules/iam"
}
```

**Benefits:**
- Same code used for dev and prod (only inputs differ)
- Reusable components
- Clean separation of concerns

## Common Commands

| Command | What it does |
|---|---|
| `terraform init` | Initialize working directory |
| `terraform plan` | Show what will change (no changes yet) |
| `terraform apply` | Make changes (after confirmation) |
| `terraform destroy` | Delete all resources |
| `terraform state list` | List all resources in state |
| `terraform state show aws_vpc.main` | Show details of one resource |
| `terraform refresh` | Update state from AWS (no changes) |
| `terraform validate` | Check syntax |
| `terraform fmt` | Auto-format code |
| `terraform output` | Show module outputs |
| `terraform version` | Show Terraform version |

## Debugging

### "Error: state is locked"

Another `terraform apply` is in progress (or crashed mid-apply).

**Check:**
```bash
aws dynamodb scan \
  --table-name devops-capstone-tfstate-lock
```

**Fix (only if you're sure the other apply isn't running):**
```bash
terraform force-unlock <lock-id>
```

### "Error: Error acquiring state lock"

DynamoDB table doesn't exist or you don't have permissions.

**Check:**
```bash
aws dynamodb describe-table \
  --table-name devops-capstone-tfstate-lock
```

### Plan shows unexpected changes

**Cause:** Drift. Someone changed something in AWS and state is out of sync.

**Check:**
```bash
terraform plan
```

If it shows changes you didn't make, investigate:
- Was the resource manually modified?
- Did someone apply a different Terraform config?
- Is there a newer version of the provider that changed behavior?

**Fix:** Either update your code to match AWS, or `terraform apply` to reset AWS to match code.

## Best Practices

1. **Always run plan before apply**
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

2. **Commit `.terraform.lock.hcl` to git**
   This pins provider version so CI/CD uses the same version as you.

3. **Never commit `.tfstate` to git**
   It's sensitive (can contain secrets) and local state is a smell.

4. **Use meaningful names**
   `aws_vpc.main`, `aws_subnet.public`, not `aws_vpc.vpc1`, `aws_subnet.subnet1`.

5. **Use `for_each` and `count` for multiple similar resources**
   Don't copy-paste resource blocks.

6. **Use outputs to expose important values**
   ```hcl
   output "vpc_id" {
     value = aws_vpc.main.id
   }
   # Then: terraform output vpc_id
   ```

7. **Use data sources to reference existing resources**
   ```hcl
   data "aws_ami" "amazon_linux" {
     filter {
       name   = "name"
       values = ["amzn2-ami-*"]
     }
   }
   ```

## Operational Lessons

**Lesson 1: State is the single source of truth**
If Terraform state says a resource exists but it's been deleted in AWS, `terraform plan` will offer to recreate it. Trust the plan output.

**Lesson 2: `terraform apply` is idempotent**
Running it twice makes no changes the second time (because state matches AWS). Safe to retry if it fails.

**Lesson 3: Destroy is scary but safe**
It only deletes what's in your code. If you didn't declare it in Terraform, it won't touch it.

**Lesson 4: Lock files prevent corruption**
DynamoDB lock table prevents two applies running simultaneously. Never bypass it.

**Lesson 5: Terraform is declarative, not imperative**
You say "I want a VPC", not "create a VPC, then create subnets, then create route tables". Terraform figures out the order and parallelizes what it can.

## Related Resources

- `docs/aws/vpc-design.md` — the VPC module explained
- `docs/iam/policy-design.md` — the IAM module explained
- `runbooks/terraform-state-recovery.md` — if state gets corrupted
- `infra/modules/` — actual Terraform code
