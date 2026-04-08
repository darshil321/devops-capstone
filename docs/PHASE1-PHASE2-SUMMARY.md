# Phase 1 & Phase 2 Complete Summary

## What You've Built

A complete DevOps foundation consisting of:

1. **NestJS application** — REST API with health checks and Prometheus metrics
2. **Docker infrastructure** — Multi-stage builds, non-root user, healthchecks, layer caching
3. **AWS VPC** — 2 public subnets, 2 private subnets, NAT Gateway, IGW, security groups
4. **IAM roles and policies** — EC2 role with S3 access, EKS node role, pod execution role
5. **Terraform infrastructure-as-code** — S3 state backend, DynamoDB locking, modular design
6. **Comprehensive documentation** — VPC design, IAM policy patterns, Terraform guide, state recovery runbook

---

## Phase 1: Docker Mastery (Weeks 1-2)

### What You Learned

| Concept | Key Insight | Use Case |
|---|---|---|
| **Multi-stage builds** | Separate build environment from runtime to reduce image size | Production Docker images |
| **Layer caching** | Docker rebuilds only the layer that changed and everything after it | Fast build pipelines |
| **Non-root user** | Running as unprivileged user reduces attack surface | Container security baseline |
| **Health checks** | Docker healthcheck cmd separate from K8s liveness/readiness probes | Container orchestration |
| **Image optimization** | Layer ordering matters: dependencies before source code | Saving minutes in CI/CD |
| **Docker exec/logs/inspect** | Debugging tools for running containers | Production incident response |

### What You Built

```dockerfile
# Three-stage Dockerfile
# Stage 1: deps        (npm ci --frozen-lockfile)
# Stage 2: builder     (npm run build — compile TypeScript)
# Stage 3: runner      (only dist + production node_modules)

# Final image: 260MB (vs 900MB with full Node)
# Runtime: node dist/main.js (not ts-node)
# User: nestjs (uid 1001, non-root)
```

### Hands-On Drills Completed

✅ `docker exec` — explore container filesystem, verify non-root user  
✅ `docker logs` — read startup sequence, debug route registration  
✅ `docker inspect` — found and fixed health check bug (`/health/live` → `/api/health/live`)  
✅ `docker stats` — baseline resource usage for idle service  
✅ `docker history` — understand layer sizes and cache behavior  
✅ Crash drill — removed entry point, observed exit code and logs  
✅ Port mapping — verified `lsof -i :3000` and `curl` connectivity  
✅ Cache invalidation — modified source file, confirmed npm ci stayed CACHED  

### Checkpoint Questions (Answered)

1. **Layer ordering fixes cache misses** — COPY package.json before COPY src/
2. **Debug crashed container** — docker ps -a, docker logs (don't use docker history)
3. **Alpine base image** — 145MB vs 900MB for full Node, reduces cost and attack surface
4. **Service discovery in docker-compose** — use service name, not localhost (bridge network DNS)

### Repo Structure Created

```
app/
├── Dockerfile                    (multi-stage, explained comments)
├── .dockerignore                 (node_modules, dist, env files)
├── docker-compose.yml            (app + postgres on bridge network)
├── src/
│   ├── main.ts                   (global prefix /api, ValidationPipe)
│   ├── app.module.ts             (PrometheusModule, TerminusModule)
│   ├── health/
│   │   └── health.controller.ts  (liveness /api/health/live, readiness /api/health/ready)
│   └── items/
│       ├── items.controller.ts   (GET/POST items endpoints)
│       └── items.service.ts      (in-memory store, swap to DB in Phase 3)
docs/docker/
├── image-build-strategy.md       (layer caching, multi-stage rationale)
├── local-dev-guide.md            (running docker-compose, service discovery)
docs/linux/
└── debugging-containers.md       (exec, logs, netstat, CrashLoopBackOff patterns)
```

### Key Commits

```
f9413b2 fix(docker): correct healthcheck path to include /api prefix
25c9205 feat(phase-1): scaffold NestJS app, multi-stage Dockerfile, docker-compose, Phase 1 docs
```

---

## Phase 2: AWS + Terraform Ownership (Weeks 3-5)

### What You Learned

| Concept | Key Insight | Use Case |
|---|---|---|
| **VPC architecture** | Public subnets + private subnets in 2 AZs = HA | All AWS infrastructure |
| **NAT Gateway** | Private instances reach internet without public IP | Securing worker nodes |
| **Terraform state** | Single source of truth stored in S3 with DynamoDB locking | Team collaboration |
| **IAM roles vs users** | Roles have temporary credentials (safer), users have static credentials | Service authentication |
| **Trust policy** | Who can assume the role (separate from permission policy) | Securing role access |
| **Least privilege** | Grant only minimum permissions needed, specific resources | Security baseline |
| **Drift detection** | terraform plan shows when AWS reality differs from desired state | Catching manual changes |

### What You Built

**VPC:**
- 1 VPC with CIDR 10.0.0.0/16
- 2 public subnets (10.0.0.0/24, 10.0.2.0/24) with IGW route
- 2 private subnets (10.0.1.0/24, 10.0.3.0/24) with NAT route
- 1 Internet Gateway (bidirectional bridge)
- 1 NAT Gateway (unidirectional for private outbound)
- 2 route tables + 4 associations
- 1 ALB security group (ports 80/443)

**IAM:**
- EC2 tfstate reader role — can read Terraform state from S3
- EKS node role — can pull images from ECR, write logs
- EKS pod execution role — placeholder for Phase 3 IRSA

**Remote State Backend:**
- S3 bucket: `devops-capstone-tfstate-890742569958`
- DynamoDB table: `devops-capstone-tfstate-lock`
- Versioning enabled (disaster recovery)
- Encryption enabled
- Public access blocked

### Hands-On Drills Completed

✅ `terraform init` — downloaded provider, created lock file  
✅ `terraform plan` — validated config, showed 15 resources to create  
✅ `terraform apply` — provisioned VPC (2m total, 1m50s for NAT)  
✅ Drift detection — manually deleted NAT route, plan detected it, apply recreated it  
✅ AWS CLI verification — confirmed resources exist in AWS  
✅ IAM policy from scratch — wrote S3 read-only policy with correct ARNs  
✅ Role creation — trust policy + permission policy verified in AWS  

### Checkpoint Questions (Answered)

1. **Private instance can't reach internet** — check SG, associations, routes, NAT status, network interface (in that order)
2. **Local routes 10.0.0.0/16** — enable cross-subnet communication, deleting breaks all VPC traffic
3. **In-place updates** — route table modified but not replaced (vs destroy+recreate)
4. **NAT Gateway slowness** — creates network interface, allocates EIP, configures NAT engine (~1m50s)
5. **Deleted route table association** — traffic drops silently, terraform plan detects drift

### Repo Structure Created

```
infra/
├── environments/dev/
│   ├── provider.tf           (AWS region, default tags, S3 backend config)
│   ├── variables.tf          (aws_region, environment, project_name)
│   └── main.tf               (instantiate vpc + iam modules)
└── modules/
    ├── vpc/
    │   ├── main.tf           (VPC, subnets, IGW, NAT, route tables, SG)
    │   ├── variables.tf       (vpc_cidr, enable_nat_gateway, AZs)
    │   └── outputs.tf         (vpc_id, subnet_ids, nat_gateway_id)
    └── iam/
        ├── main.tf           (3 roles, 3 instance profiles, policies)
        ├── variables.tf       (project_name, environment, tags)
        └── outputs.tf         (role ARNs, instance profile ARNs)

docs/
├── aws/
│   └── vpc-design.md         (architecture, CIDR strategy, NGW vs IGW, debugging)
├── iam/
│   └── policy-design.md      (principal/action/resource, trust vs permission, least privilege)
└── terraform/
    └── getting-started.md    (workflow, state file, modules, debugging)

runbooks/
└── terraform-state-recovery.md  (restore from S3 versioning, force-unlock, re-import)
```

### Key Commits

```
89d9f71 docs(phase-2): VPC design, IAM policy guide, Terraform getting started, state recovery runbook
4888ed2 feat(phase-2): IAM module with EC2 role, EKS node role, pod execution role
8df7a7e feat(phase-2): VPC module with public/private subnets, IGW, NAT Gateway
```

---

## Critical Insights

### Insight 1: State is Sacred

**Problem:** Terraform state is the single source of truth. If corrupted, you can't manage infrastructure.

**Solution:** 
- S3 with versioning enabled (automatic backups)
- DynamoDB locking prevents concurrent applies
- Always run `terraform plan` before `apply`

**Operational impact:** A 2-minute state recovery beats 2 hours of manual infrastructure recreation.

### Insight 2: Drift Detection is Continuous

**Pattern:** Terraform detects when AWS reality diverges from desired state.

```
Someone manually deletes NAT route
→ terraform plan detects it missing
→ terraform apply recreates it
→ No silent failures
```

**Why it matters:** Without drift detection, you'd only discover the problem when a pod couldn't reach the internet.

### Insight 3: Layers of Abstraction Save Time

**Phase 1:** NestJS app → Dockerfile → Docker image  
**Phase 2:** Infrastructure → Terraform modules → AWS resources  
**Phase 3:** Images + modules → EKS → Running cluster  
**Phase 4:** EKS + images → Jenkins pipeline → Automated deployment  
**Phase 5:** Running services → Prometheus → Metrics + alerts  

Each layer builds on the previous. Skipping any layer means rework later.

### Insight 4: Security is Layer 0

**Phase 1:** Non-root user in container  
**Phase 2:** IAM least privilege, private subnets, encrypted state  
**Phase 3:** RBAC in K8s, pod security policies  
**Phase 4:** Jenkins pipeline authentication, artifact signing  
**Phase 5:** Prometheus auth, alert channel encryption  

Security isn't added after; it's baked in from the start.

### Insight 5: Immutability Prevents Foot Guns

**Docker layers:** Immutable history prevents confusion about what changed  
**IAM policies:** JSON documents that can be version-controlled  
**Terraform state:** Versioned in S3, can restore any previous state  
**Git commits:** Immutable history of what changed and why  

**Operational benefit:** When something breaks, you can pinpoint exactly what changed.

---

## From Here to Phase 3

**Phase 3: ECR + EKS + Kubernetes Ownership** (Weeks 6-8)

You'll provision an EKS cluster and deploy your NestJS service to it. This requires:

1. **ECR repository** — for pushing Docker images
2. **EKS cluster** — managed Kubernetes in AWS
3. **K8s objects** — Deployments, Services, ConfigMaps, Ingress, HPA, RBAC
4. **Pod execution role** — IRSA (IAM Roles for Service Accounts)
5. **Security groups** — node-to-node, pod-to-pod, ALB-to-pod communication

The VPC you built (public/private subnets, NAT) is where the EKS cluster will run. The IAM roles you created are what the nodes will assume. The Terraform structure you established will scale to 100+ resources.

---

## Repository State

**Master branch:** 4 commits, clean working tree

```
89d9f71 docs(phase-2): VPC design, IAM policy guide, Terraform getting started, state recovery runbook
4888ed2 feat(phase-2): IAM module with EC2 role, EKS node role, pod execution role
8df7a7e feat(phase-2): VPC module with public/private subnets, IGW, NAT Gateway
f9413b2 fix(docker): correct healthcheck path to include /api prefix
25c9205 feat(phase-1): scaffold NestJS app, multi-stage Dockerfile, docker-compose, Phase 1 docs
```

**AWS state:** VPC and IAM roles destroyed (to avoid NAT Gateway costs). State file preserved in S3.

**Local state:** `.terraform.lock.hcl` committed (provider version pinning)

---

## Self-Assessment

### What Clicked

- **Docker internals** — You understand layer caching, multi-stage builds, and why the final image is 260MB
- **Terraform workflow** — init → plan → apply → destroy is now muscle memory
- **IAM fundamentals** — Principal/action/resource makes sense, trust policy vs permission policy distinction is clear
- **Debugging mindset** — You know to check SG → routes → health status in order

### What Needs Deepening

- **Terraform modules** — You understand the structure but haven't written one from scratch yet (Phase 3)
- **K8s networking** — You know VPC layout, but pod networking (CNI) is still abstract
- **Observability** — Prometheus/Grafana come in Phase 5; metrics instrumentation not yet written

### What to Practice Before Phase 3

1. **Write a custom IAM policy from scratch** — for a different use case (RDS access, Lambda invoke)
2. **Manually create a Terraform module** — not just instantiate, but write variables.tf + main.tf + outputs.tf
3. **Destroy and recreate the VPC** — twice, to make `terraform destroy` comfortable
4. **Read three AWS IAM policies** — AWS managed ones, understand what each action does

---

## Key Files to Know

| File | Purpose | Read When |
|---|---|---|
| `app/Dockerfile` | Multi-stage build reference | Building Docker images |
| `infra/modules/vpc/main.tf` | VPC architecture | Understanding networking |
| `infra/modules/iam/main.tf` | IAM role examples | Writing policies |
| `docs/aws/vpc-design.md` | VPC design decisions | Debugging network issues |
| `docs/iam/policy-design.md` | Policy patterns | Writing new IAM policies |
| `docs/terraform/getting-started.md` | Terraform workflow | Running Terraform commands |
| `runbooks/terraform-state-recovery.md` | Disaster recovery | State is corrupted |

---

## Timeline Summary

**Phase 1 Week 1:** Docker mastery (Dockerfile, healthchecks, layer caching) — 20 hours  
**Phase 1 Week 2:** Docker drills (exec, logs, inspect, crash testing) — pending completion  

**Phase 2 Week 1:** VPC from scratch (public/private subnets, NAT, routing) — 12 hours  
**Phase 2 Week 2:** IAM from scratch (policies, roles, trust relationships) — 8 hours  
**Phase 2 Week 3:** Security groups, docs, checkpoint questions — pending  

**Total Phase 1-2:** ~40 hours (on track for 18-week capstone)

---

## Next Steps

1. **Review the docs** you just committed — they're your personal DevOps handbook
2. **Update memory** with key operational insights
3. **Before Phase 3 Week 1:** Destroy and recreate the VPC twice to build confidence
4. **Study:** EKS architecture, K8s object model, container networking (CNI)

You've built the foundation. Phase 3 is where it all runs.
