# VPC Design Architecture

## What It Is

A Virtual Private Cloud (VPC) is your isolated network in AWS. It's where all your infrastructure lives — instances, databases, load balancers. Everything that communicates needs to be inside or routed through a VPC.

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│ VPC: 10.0.0.0/16                                   │
│                                                     │
│  ┌──────────────────────┐  ┌──────────────────────┐│
│  │ AZ us-east-1a        │  │ AZ us-east-1b        ││
│  │                      │  │                      ││
│  │ ┌──────────────────┐ │  │ ┌──────────────────┐ ││
│  │ │ Public Subnet    │ │  │ │ Public Subnet    │ ││
│  │ │ 10.0.0.0/24      │ │  │ │ 10.0.2.0/24      │ ││
│  │ │ (IGW route)      │ │  │ │ (IGW route)      │ ││
│  │ └──────────────────┘ │  │ └──────────────────┘ ││
│  │          │           │  │          │           ││
│  │ ┌──────────────────┐ │  │ ┌──────────────────┐ ││
│  │ │ Private Subnet   │ │  │ │ Private Subnet   │ ││
│  │ │ 10.0.1.0/24      │ │  │ │ 10.0.3.0/24      │ ││
│  │ │ (NAT route)      │ │  │ │ (NAT route)      │ ││
│  │ └──────────────────┘ │  │ └──────────────────┘ ││
│  │          │           │  │          │           ││
│  └──────────┼───────────┘  └──────────┼───────────┘│
│             │                         │            │
│  ┌──────────┴─────────────────────────┴──────────┐ │
│  │         NAT Gateway (us-east-1a)              │ │
│  │  Translates private IPs to public IP          │ │
│  └────────────────────┬─────────────────────────┘ │
│                       │                            │
│  ┌────────────────────┴─────────────────────────┐ │
│  │      Internet Gateway                        │ │
│  │  Bidirectional: VPC ↔ Internet               │ │
│  └──────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
         │
         └──────────────► Internet (0.0.0.0/0)
```

## CIDR Block Strategy

**VPC CIDR:** `10.0.0.0/16` (65,536 usable IPs)

**Subnet breakdown:**
- Public subnet 1 (AZ-a): `10.0.0.0/24` (256 IPs)
- Public subnet 2 (AZ-b): `10.0.2.0/24` (256 IPs)
- Private subnet 1 (AZ-a): `10.0.1.0/24` (256 IPs)
- Private subnet 2 (AZ-b): `10.0.3.0/24` (256 IPs)

**Why this pattern?**
- `/24` subnets are large enough for most use cases (EC2, RDS, Pods)
- Interleaving public/private (0, 1, 2, 3) makes visually scanning configs easier
- Leaving room (10.0.4.0 onwards) for future expansion without redesign
- Each AZ has one public and one private subnet for HA

**GCP equivalent:** VPC with custom subnets, same principles apply

## Public vs Private Subnets

### Public Subnets
- **Route:** 0.0.0.0/0 → Internet Gateway
- **Use case:** Load balancers, NAT Gateway, bastion hosts
- **Inbound:** Can receive traffic from internet (if security group allows)
- **Outbound:** Direct path to internet
- **In our setup:** ALB Ingress Controller runs here

### Private Subnets
- **Route:** 0.0.0.0/0 → NAT Gateway
- **Use case:** EC2 instances, RDS, EKS worker nodes, application services
- **Inbound:** Cannot receive unsolicited traffic from internet
- **Outbound:** Routed through NAT Gateway (appears to come from NAT's public IP)
- **In our setup:** EKS nodes run here

## Internet Gateway vs NAT Gateway

### Internet Gateway (IGW)
- **What it is:** Bidirectional bridge between VPC and internet
- **Cost:** Free
- **Traffic:** Both inbound and outbound
- **Use case:** Public subnets, load balancers
- **Example:** ALB receives inbound HTTPS request → IGW routes it into VPC

### NAT Gateway
- **What it is:** Unidirectional translator (outbound only)
- **Cost:** ~$32/month + $0.045/hour usage
- **Traffic:** Outbound only (outbound is translated, inbound is not accepted)
- **Use case:** Private subnets needing internet access
- **Example:** Private EC2 instance does `apt update` → NAT translates source IP → response comes back to NAT → NAT translates back to private IP
- **Key insight:** Private instance has no public IP, but can reach the internet because NAT masquerades the traffic

**Why not use IGW for private subnets?**
Because IGW provides bidirectional access. A private instance with IGW route would be reachable from the internet, defeating the purpose of having a private subnet. NAT prevents inbound while allowing outbound.

## Route Tables

**Public route table:**
```
Destination     Target          Scope
10.0.0.0/16     local           Within VPC
0.0.0.0/0       igw-xxxxx       To internet
```

**Private route table:**
```
Destination     Target          Scope
10.0.0.0/16     local           Within VPC
0.0.0.0/0       nat-xxxxx       To internet (via NAT)
```

**Critical:** Route tables are created but useless without associations. A subnet must be explicitly associated with a route table, or it uses the VPC's default (which has only local routes).

## Security Groups

**ALB Security Group:**
- **Ingress:** Port 80 (HTTP), Port 443 (HTTPS) from 0.0.0.0/0
- **Egress:** All traffic to 0.0.0.0/0
- **Purpose:** Allow internet traffic to reach the load balancer

**Node Security Group** (created in Phase 3):
- **Ingress:** Port 443 from VPC CIDR (pod-to-pod communication via CNI)
- **Egress:** All traffic
- **Purpose:** Allow pods to communicate within the cluster

## Debugging Guide

### "Private instance can't reach the internet"

Check in this order:

1. **Security group egress rules**
   ```bash
   aws ec2 describe-security-groups --group-ids sg-xxxxx
   # Look for egress rule allowing 0.0.0.0/0
   ```

2. **Route table association**
   ```bash
   aws ec2 describe-route-tables \
     --filters "Name=association.subnet-id,Values=subnet-xxxxx"
   # Should return a route table with NAT route
   ```

3. **Route exists**
   ```bash
   aws ec2 describe-route-tables --route-table-ids rtb-xxxxx
   # Should show: 0.0.0.0/0 → nat-xxxxx
   ```

4. **NAT Gateway status**
   ```bash
   aws ec2 describe-nat-gateways --nat-gateway-ids nat-xxxxx
   # Should show State: available
   ```

5. **Instance network interface**
   ```bash
   aws ec2 describe-instances --instance-ids i-xxxxx
   # Check PrivateIpAddress and PrivateIpAddresses
   ```

### "Public instance can't reach the internet"

1. Check security group has egress 0.0.0.0/0
2. Check route table association
3. Check route table has 0.0.0.0/0 → IGW
4. Check IGW is attached to VPC: `aws ec2 describe-internet-gateways`

### "Two instances in same VPC can't communicate"

1. Check both instances are in the same VPC
2. Check security group ingress allows traffic between them (or from security group to security group)
3. Check route tables both have local 10.0.0.0/16 route
4. Check Network ACLs (rarely the problem, but possible)

## Operational Lessons

**Lesson 1: NAT Gateway is expensive**
At 1m50s provisioning + $32/month, it's the biggest cost in a dev VPC. For testing, disable it via `enable_nat_gateway = false` and destroy to save costs.

**Lesson 2: Route table associations are silent failures**
If a subnet isn't associated, traffic drops silently with no error. Always verify associations exist after changes.

**Lesson 3: Terraform drift detection catches manual deletes**
When we manually deleted the NAT route, `terraform plan` caught it immediately. Always run plan before apply.

**Lesson 4: AZ distribution matters**
Spreading subnets across 2 AZs means if AWS loses one AZ, your infrastructure stays online. Single-AZ is never acceptable for production.

## GCP Mapping

| AWS | GCP |
|---|---|
| VPC | VPC Network |
| Public subnet | Subnet with Cloud NAT disabled, IGW-equivalent |
| Private subnet | Subnet with Cloud NAT enabled |
| Internet Gateway | Cloud Router + Cloud NAT (for egress) |
| NAT Gateway | Cloud NAT |
| Route table | Routes within VPC |
| Security group | Firewall Rules |

## Related Resources

- `docs/terraform/module-patterns.md` — how VPC module is structured
- `infra/modules/vpc/` — the actual Terraform code
- `runbooks/terraform-state-recovery.md` — if state gets corrupted
