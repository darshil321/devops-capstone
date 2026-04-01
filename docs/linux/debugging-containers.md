# Linux Container Debugging — Personal Cheat Sheet

## Why You Need This
When a pod crashes in EKS at 3am, you won't have a GUI.
You'll have kubectl and a terminal. These commands are your toolkit.

---

## Getting Inside a Container / Pod

```bash
# Docker (local)
docker exec -it <container_id_or_name> sh    # Alpine-based images use sh, not bash
docker exec -it <container_id> bash          # Debian/Ubuntu-based images

# Kubernetes
kubectl exec -it <pod_name> -- sh
kubectl exec -it <pod_name> -c <container_name> -- sh   # multi-container pod
```

**Common mistake**: Trying `bash` on an Alpine image → "bash: not found". Use `sh`.

---

## Reading Logs

```bash
# Docker
docker logs <container_id>                  # all logs
docker logs -f <container_id>               # follow (tail -f equivalent)
docker logs --tail 100 <container_id>       # last 100 lines
docker logs --since 5m <container_id>       # last 5 minutes

# Kubernetes
kubectl logs <pod_name>                     # current pod logs
kubectl logs -f <pod_name>                  # follow
kubectl logs --previous <pod_name>          # logs from the PREVIOUS crashed container
kubectl logs <pod_name> -c <container>      # specific container in multi-container pod
```

**Pro tip**: `kubectl logs --previous` is your first command when a pod is in CrashLoopBackOff.
It shows the logs from the container that just crashed, before it was restarted.

---

## Checking Environment Variables

```bash
# Inside the container
env                         # all env vars
env | grep DATABASE         # grep for specific ones
printenv DATABASE_URL        # single var

# From outside the pod (Kubernetes)
kubectl exec <pod> -- env
kubectl describe pod <pod> | grep -A 5 "Environment"
```

**CrashLoopBackOff pattern**: App crashes on start → `kubectl logs --previous` →
`Error: DATABASE_URL is not defined` → missing env var in deployment ConfigMap/Secret.

---

## Checking Network Connectivity

```bash
# From INSIDE the container — test if you can reach another service
curl http://other-service:3000/health       # by service name (K8s DNS)
curl http://10.0.1.45:5432                  # by IP directly

# DNS resolution check (is the K8s service discoverable?)
nslookup postgres                           # resolve service name
nslookup postgres.default.svc.cluster.local # fully qualified K8s DNS name

# Is the port actually open? (check if process is listening)
netstat -tlnp                               # all listening ports with process
ss -tlnp                                    # modern replacement for netstat
lsof -i :3000                               # what's using port 3000

# TCP connectivity test (curl alternative)
wget -qO- http://localhost:3000/health/live
nc -zv postgres 5432                        # netcat: can we reach postgres:5432?
```

**GCP vs AWS**: In GCP, services communicate via VPC. In EKS, pods use K8s DNS
(ClusterIP Services). The service name resolves within the cluster namespace.
`postgres` resolves to `postgres.default.svc.cluster.local` automatically.

---

## Checking Resource Usage

```bash
# Inside container
top                         # CPU + memory for all processes (q to quit)
ps aux                      # all processes
cat /proc/meminfo           # memory details
df -h                       # disk usage (watch for log-filled /var)

# From outside — Kubernetes
kubectl top pod <pod_name>                      # CPU + memory (needs metrics-server)
kubectl top pod -n <namespace>                  # all pods in namespace
kubectl top node                                # node-level resource pressure
kubectl describe node <node_name> | grep -A 10 "Allocated resources"
```

**No metrics?** If `kubectl top` returns "metrics not available", metrics-server
is not installed. Check: `kubectl get deployment metrics-server -n kube-system`.

---

## Diagnosing Pod Status

```bash
kubectl get pods                                 # summary status
kubectl describe pod <pod_name>                  # FULL details: events, probe failures, restart reasons
kubectl get pod <pod_name> -o yaml               # raw YAML including status conditions

# What each status means:
# Pending       → not scheduled yet (insufficient resources, unbound PVC, or node selector mismatch)
# CrashLoopBackOff → container starts and exits repeatedly (usually bad config or crash on init)
# OOMKilled     → pod killed by kernel, exceeded memory limit
# ImagePullBackOff → can't pull image (ECR auth, wrong tag, private registry not configured)
# Terminating   → pod is being deleted (stuck = finalizer issue)
# ContainerCreating → waiting for volume mount or image pull
```

---

## The CrashLoopBackOff Debugging Flow

When you see `CrashLoopBackOff`:

```bash
# Step 1: Get the exit code from the crashed container
kubectl describe pod <pod> | grep "Exit Code"

# Step 2: Read the crash logs (from previous run)
kubectl logs --previous <pod>

# Step 3: Common exit codes
# Exit 1  → unhandled exception / app error (read the logs)
# Exit 137 → OOMKilled (increase memory limit or find the leak)
# Exit 139 → Segfault (rare in Node.js, but possible in native modules)
# Exit 143 → SIGTERM not handled (app didn't gracefully shutdown)

# Step 4: Check env vars — missing required config is #1 cause
kubectl exec <pod> -- env | grep -i required_var

# Step 5: Reproduce locally
docker run --env-file .env devops-capstone:v1
```

---

## Port Forwarding for Local Debugging

```bash
# Forward a K8s pod port to localhost for manual testing
kubectl port-forward pod/<pod_name> 3000:3000
kubectl port-forward svc/<service_name> 3000:3000

# Now you can curl the pod directly from your machine
curl http://localhost:3000/api/health/live
```

---

## Related Resources
- [K8s Probes Guide](../kubernetes/probes-guide.md)
- [CrashLoopBackOff Runbook](../../runbooks/crashloopbackoff.md)
- [image-build-strategy.md](./image-build-strategy.md)
