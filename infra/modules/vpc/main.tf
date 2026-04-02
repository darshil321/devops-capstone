# =============================================================================
# VPC MODULE
# =============================================================================
# This module provisions a complete VPC with public and private subnets
# distributed across 2 availability zones for high availability.
#
# Architecture:
#   - 1 VPC with configurable CIDR
#   - 2 public subnets (one per AZ) — route to internet via IGW
#   - 2 private subnets (one per AZ) — route to internet via NAT Gateway
#   - Internet Gateway (IGW) — allows traffic from internet to public subnets
#   - NAT Gateway — allows private subnet instances to reach internet without inbound
#   - Route tables and associations
#   - Security group for ALB (will be used by EKS)
#
# The key insight: private subnets need a path to the internet for:
#   - Pulling Docker images from ECR
#   - Downloading OS updates
#   - Reaching external APIs
# But they shouldn't accept inbound traffic from the internet. NAT provides that.
# =============================================================================

# Create the VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}

# =============================================================================
# PUBLIC SUBNETS (2 across 2 AZs)
# =============================================================================
# Public subnets have route to IGW. Instances here can reach internet and
# can be reached from internet (if security group allows).
# EKS ALB Ingress Controller runs here.
# =============================================================================

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index * 2}.0/24"
  availability_zone      = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-public-subnet-${count.index + 1}"
      Tier = "Public"
    }
  )
}

# =============================================================================
# PRIVATE SUBNETS (2 across 2 AZs)
# =============================================================================
# Private subnets do NOT have direct route to internet.
# EKS worker nodes and Postgres run here.
# They reach internet via NAT Gateway in the public subnet.
# =============================================================================

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index * 2 + 1}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-private-subnet-${count.index + 1}"
      Tier = "Private"
    }
  )
}

# =============================================================================
# INTERNET GATEWAY
# =============================================================================
# Allows traffic between the VPC and the internet.
# Required for public subnets to reach the internet.
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

# =============================================================================
# NAT GATEWAY (only if enabled)
# =============================================================================
# Allows private subnet instances to reach the internet.
# Requires an Elastic IP address (static public IP).
# NOTE: NAT Gateway costs ~$32/month + $0.045/hour. This is the most
# expensive part of the VPC in dev. We'll destroy it after testing.
# =============================================================================

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-eip"
    }
  )
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-gateway"
    }
  )
}

# =============================================================================
# ROUTE TABLES
# =============================================================================
# Route tables define where traffic goes based on destination CIDR.
#
# Public route table:
#   - 10.0.0.0/16 → local (within VPC)
#   - 0.0.0.0/0 → IGW (to internet)
#
# Private route table:
#   - 10.0.0.0/16 → local (within VPC)
#   - 0.0.0.0/0 → NAT Gateway (to internet via NAT)
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}

resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-private-rt"
    }
  )
}

# =============================================================================
# ROUTE TABLE ASSOCIATIONS
# =============================================================================
# Associate subnets with route tables.
# Without this, subnets use the VPC's main route table (which has no IGW/NAT).
# This is the #1 networking misconfiguration in Terraform — routes defined
# but not associated, so traffic silently drops.
# =============================================================================

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.enable_nat_gateway ? aws_route_table.private[0].id : aws_route_table.public.id
}

# =============================================================================
# SECURITY GROUP FOR ALB
# =============================================================================
# This security group allows ingress from internet on ports 80/443.
# EKS ALB Ingress Controller will use this for the Application Load Balancer.
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-alb-sg"
    }
  )
}
