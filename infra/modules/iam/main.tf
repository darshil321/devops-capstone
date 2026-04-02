# =============================================================================
# IAM MODULE
# =============================================================================
# This module provisions IAM roles and policies for the infrastructure.
#
# In Phase 2 Week 2, we create:
#   1. EC2 instance role — allows EC2 to read Terraform state from S3
#   2. EKS node role — will be used in Phase 3 (stubbed here)
#   3. EKS pod execution role — will be used in Phase 3 (stubbed here)
#
# Key principle: least privilege. Each role gets only the minimum permissions
# it needs. A role that only reads S3 cannot create VPCs.
# =============================================================================

# =============================================================================
# EC2 INSTANCE ROLE — READ TERRAFORM STATE
# =============================================================================
# This role allows EC2 instances to read the Terraform state file from S3.
# Use case: EC2 instances that need to query infrastructure state (e.g.,
# a monitoring agent that needs VPC CIDR to configure routing).
# =============================================================================

# Trust policy: EC2 service can assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Permission policy: Read S3 terraform state bucket
data "aws_iam_policy_document" "ec2_read_tfstate" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::devops-capstone-tfstate-${data.aws_caller_identity.current.account_id}",
      "arn:aws:s3:::devops-capstone-tfstate-${data.aws_caller_identity.current.account_id}/*"
    ]
  }
}

# Get the current AWS account ID
data "aws_caller_identity" "current" {}

# Create the IAM role
resource "aws_iam_role" "ec2_tfstate_reader" {
  name               = "${var.project_name}-ec2-tfstate-reader"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ec2-tfstate-reader"
    }
  )
}

# Attach the permission policy to the role
resource "aws_iam_role_policy" "ec2_read_tfstate" {
  name   = "${var.project_name}-ec2-read-tfstate"
  role   = aws_iam_role.ec2_tfstate_reader.id
  policy = data.aws_iam_policy_document.ec2_read_tfstate.json
}

# Instance profile — required to attach a role to an EC2 instance
resource "aws_iam_instance_profile" "ec2_tfstate_reader" {
  name = "${var.project_name}-ec2-tfstate-reader"
  role = aws_iam_role.ec2_tfstate_reader.name
}

# =============================================================================
# EKS NODE ROLE (PHASE 3)
# =============================================================================
# Placeholder for EKS worker node role. In Phase 3, this will have permissions
# for: pulling images from ECR, reading CloudWatch logs, using EBS volumes.
# =============================================================================

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_node_role" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-node-role"
    }
  )
}

# Attach AWS managed policy for EKS nodes
# This policy grants permissions for: ECR pull, EBS, CloudWatch Logs, VPC CNI
resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "eks_node_profile" {
  name = "${var.project_name}-eks-node-profile"
  role = aws_iam_role.eks_node_role.name
}

# =============================================================================
# EKS POD EXECUTION ROLE (PHASE 3)
# =============================================================================
# Placeholder for EKS pod execution role (IRSA — IAM Roles for Service Accounts).
# Pods in the cluster will assume this role to access AWS services.
# =============================================================================

data "aws_iam_policy_document" "eks_pod_assume_role" {
  # This will be populated in Phase 3 when we have the OIDC provider
  statement {
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_pod_execution_role" {
  name               = "${var.project_name}-eks-pod-execution-role"
  assume_role_policy = data.aws_iam_policy_document.eks_pod_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-pod-execution-role"
    }
  )
}
