# =============================================================================
# EKS MODULE
# =============================================================================
# Elastic Kubernetes Service (EKS) — managed Kubernetes in AWS.
#
# Components:
#   1. EKS Cluster (control plane) — managed by AWS
#   2. Node Group (worker nodes) — EC2 instances managed by AWS Auto Scaling
#   3. Security groups — networking rules
#   4. IAM roles — permissions for nodes
#
# Cost breakdown (dev cluster, 2 t3.medium nodes):
#   - Control plane: $0.10/hour = $72/month
#   - 2 x t3.medium nodes: ~$0.0416 * 2 * 730 = ~$61/month
#   - Total: ~$133/month
#
# GCP equivalent: Google Kubernetes Engine (GKE)
# Azure equivalent: Azure Kubernetes Service (AKS)
# =============================================================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# =============================================================================
# EKS CLUSTER CONTROL PLANE
# =============================================================================
# The control plane is managed by AWS:
#   - You don't see the EC2 instances running the control plane
#   - AWS patches and upgrades them automatically
#   - You pay a fixed fee ($0.10/hour) regardless of workload size
#
# What you provide:
#   - VPC and subnets where the cluster runs
#   - IAM role for the cluster (created below)
#   - Security group controlling access to the API server
#
# What you get:
#   - Kubernetes API server (kubectl connects here)
#   - etcd (Kubernetes state database, managed by AWS)
#   - Controller managers, scheduler (all managed)
#
# You own the worker nodes (EC2 instances), AWS owns the control plane.
# =============================================================================

# IAM role for the EKS cluster control plane
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-cluster-role"
    }
  )
}

# Attach AWS managed policy to cluster role
# This grants the cluster permission to manage ENIs, security groups, VPC, etc.
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Attach VPC management policy (for managing ENIs and security groups)
resource "aws_iam_role_policy_attachment" "cluster_vpc_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# Security group for the cluster control plane
# Controls what can access the Kubernetes API server
resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-eks-cluster-"
  description = "EKS cluster security group"
  vpc_id      = var.vpc_id

  # Allow worker nodes to communicate with cluster API
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [var.node_security_group_id]
    description = "Allow nodes to call the cluster API"
  }

  # Allow all egress (cluster needs to reach nodes, internet, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-cluster-sg"
    }
  )
}

# The actual EKS cluster resource
resource "aws_eks_cluster" "main" {
  name            = "${var.project_name}-${var.environment}"
  version         = var.kubernetes_version
  role_arn        = aws_iam_role.cluster.arn

  vpc_config {
    # Deploy cluster in private subnets (more secure)
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true  # Needed for kubectl from your laptop
  }

  # Enable logging for audit and other purposes (optional, can add in Phase 5)
  enabled_cluster_log_types = []  # "" means no logging for now

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_policy,
  ]
}

# =============================================================================
# EKS NODE GROUP (Worker Nodes)
# =============================================================================
# Managed node group = AWS Auto Scaling group that manages EC2 instances.
#
# What AWS does:
#   - Spins up/down EC2 instances based on desired count
#   - Applies IAM role to instances
#   - Joins instances to the cluster
#   - Handles node upgrades (rolling restart)
#
# What you provide:
#   - Instance type (t3.medium)
#   - Desired count (2)
#   - IAM role for nodes (created in iam module)
#   - Subnets (where to launch instances)
#   - Security group (networking rules)
# =============================================================================

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-nodes"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.desired_node_count
    max_size     = var.max_node_count
    min_size     = var.min_node_count
  }

  instance_types = [var.node_instance_type]

  # Enable bootstrapping (join to cluster automatically)
  # The node bootstrap process will:
  #   - Install kubelet, container runtime
  #   - Configure it to join the cluster
  #   - Start the kubelet service
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-node-group"
    }
  )

  # This tells Terraform to wait for nodes to be healthy before proceeding
  depends_on = [
    aws_eks_cluster.main,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# node_to_cluster_api rule is already defined inline in aws_security_group.cluster above.
# Mixing inline rules and aws_security_group_rule resources for the same SG causes duplicates.
