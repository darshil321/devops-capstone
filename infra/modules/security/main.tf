# =============================================================================
# SECURITY MODULE
# =============================================================================
# Security groups for EKS networking.
#
# Three separate security groups:
#   1. Node security group — EKS worker nodes
#   2. Pod security group — Pods running on nodes (optional in Phase 3)
#   3. ALB security group — already exists in VPC module, but referenced here
#
# Key insight: Security groups are stateful. If you allow ingress on port 443,
# return traffic is automatically allowed. No need for explicit egress rules
# for responses. However, we explicitly allow 0.0.0.0/0 egress to be clear.
# =============================================================================

# =============================================================================
# EKS NODE SECURITY GROUP
# =============================================================================
# Applied to EC2 instances that are EKS worker nodes.
#
# Ingress rules:
#   - Port 443 from VPC CIDR (for pod-to-pod communication via CNI)
#   - Port 10250 from VPC CIDR (kubelet API, for kube-proxy/metrics-server)
#   - Port 1025-65535 from self (ephemeral ports for node-to-node communication)
#
# Egress rules:
#   - All traffic to 0.0.0.0/0 (nodes need to pull images, reach APIs, etc.)
#
# Why separate from ALB SG?
#   - Nodes and ALB have different traffic patterns
#   - Nodes need kubelet ports (443, 10250), ALB doesn't
#   - Makes security auditing clearer
# =============================================================================

resource "aws_security_group" "node" {
  name_prefix = "${var.project_name}-node-"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-node-sg"
    }
  )
}

# Allow node-to-node communication (ephemeral ports)
resource "aws_security_group_rule" "node_to_node" {
  type              = "ingress"
  from_port         = 1025
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.node.id
}

# Allow pod-to-pod communication via CNI (port 443)
resource "aws_security_group_rule" "pod_to_pod" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
}

# Allow kubelet API access (for metrics-server, kube-proxy)
resource "aws_security_group_rule" "kubelet_api" {
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
}

# Allow all outbound traffic (nodes need to pull images, update packages, reach APIs)
resource "aws_security_group_rule" "node_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}

# =============================================================================
# ALB TO NODE TRAFFIC
# =============================================================================
# Allow ALB security group to reach nodes on port 443 (ALB → kubelet)
# This is how the ALB Ingress Controller communicates with the cluster.
# =============================================================================

# Note: We don't have ALB SG ID passed here, so we'll handle this in Phase 3
# by allowing traffic from the VPC CIDR. In Phase 4, we'll tighten this.

# Allow ALB (from VPC) to reach node port range
resource "aws_security_group_rule" "alb_to_node" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
  description       = "ALB to NodePort services"
}

# =============================================================================
# POD SECURITY GROUP (for future use)
# =============================================================================
# In Phase 3, pods inherit the node security group.
# In Phase 5 (advanced networking), we'll use separate pod security groups
# for fine-grained control over pod-to-pod communication.
# For now, just create an empty one as a placeholder.
# =============================================================================

resource "aws_security_group" "pod" {
  name_prefix = "${var.project_name}-pod-"
  description = "EKS pod security group (future use)"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-pod-sg"
    }
  )
}

# Allow pod-to-pod communication
resource "aws_security_group_rule" "pod_to_pod_internal" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.pod.id
}

resource "aws_security_group_rule" "pod_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pod.id
}
