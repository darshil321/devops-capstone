# Docker Image Build Strategy

## What It Is
A multi-stage Docker build separates the image construction into discrete phases.
Each phase discards what the next phase doesn't need. The final image only contains
what the runtime needs — no build tools, no source code, no dev dependencies.

## Why It Matters In Production
A naive single-stage build for a NestJS app produces a ~800MB image.
Our multi-stage build produces ~234MB. This affects:

- **ECR storage cost**: Every pushed image tag sits in ECR. 10 deploys/day × 600MB saved = 6GB/day less storage.
- **Pipeline speed**: Jenkins pulls this image onto EKS nodes. A 200MB pull takes ~10s. An 800MB pull takes ~40s. Multiply across rolling deployments.
- **Attack surface**: Every package in your image is a potential CVE. DevDependencies (typescript, eslint, jest) have no business being in a production pod.
- **Pod startup time**: Smaller image = faster pull = faster pod schedule = faster recovery during incidents.

## How It Works

### Stage 1: deps
```dockerfile
FROM node:20-alpine AS deps
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile
```
**Purpose**: Install all dependencies (including dev) so TypeScript can compile.
**Layer cache**: This stage is only re-executed when `package.json` or `package-lock.json` changes.
Changing a `.ts` file does NOT invalidate this cache.

### Stage 2: builder
```dockerfile
FROM node:20-alpine AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build
```
**Purpose**: Compile TypeScript to JavaScript (`dist/`).
**Layer cache**: Only invalidated when source files change (which is expected on every commit).
The `node_modules` are pulled from the `deps` stage cache — no re-install.

### Stage 3: runner (final image)
```dockerfile
FROM node:20-alpine AS runner
RUN addgroup -g 1001 -S nodejs && adduser -S nestjs -u 1001
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile --omit=dev   # production deps only
COPY --from=builder /app/dist ./dist
USER nestjs
CMD ["node", "dist/main.js"]
```
**Purpose**: Minimal runtime image. No TypeScript. No build tools. Runs as non-root.
**What's excluded**: All devDependencies (~120MB of typescript, jest, eslint, ts-node, etc.)

## Layer Cache — The Critical Mental Model

Docker builds images as a stack of immutable layers.
When a layer changes, Docker **invalidates that layer and every layer after it**.

```
# BAD: npm install runs on every build because COPY . . changes first
FROM node:20-alpine
COPY . .                        ← source changes invalidate cache here
RUN npm install                 ← runs every time, even if package.json didn't change

# GOOD: npm install is cached unless package.json changes
FROM node:20-alpine
COPY package.json package-lock.json ./   ← only changes when deps change
RUN npm install                          ← cached as long as package.json is stable
COPY . .                                 ← source changes only invalidate COPY + tsc
```

**Rule**: Always copy files that change infrequently BEFORE files that change often.

## Common Failure Modes

| Failure | Symptom | Root Cause | Fix |
|---|---|---|---|
| Cache miss on every build | `npm ci` runs even for `.ts` changes | `COPY . .` before `COPY package.json` | Reorder COPY instructions |
| `node_modules` in image | Image is 800MB+ | `.dockerignore` missing or wrong | Add `node_modules/` to `.dockerignore` |
| Build succeeds but app crashes | `class-validator not found` at runtime | Missing prod dep | Move to `dependencies`, not `devDependencies` |
| Non-root user can't start | Permission denied on `/app` | WORKDIR owned by root | Add `RUN chown` or set `WORKDIR` after `USER` |
| Image runs ts-node in prod | App works but startup is slow | `CMD ["ts-node", "src/main.ts"]` | Use `node dist/main.js` in runner stage |

## Debugging Commands

```bash
# See all layers and their sizes
docker history devops-capstone:v1

# Check final image size
docker images devops-capstone:v1

# Inspect image metadata (user, entrypoint, env)
docker inspect devops-capstone:v1 | jq '.[0].Config'

# Run interactively to explore the filesystem
docker run -it --rm devops-capstone:v1 sh

# Check what's running inside a live container
docker exec -it <container_id> sh
ps aux                  # what processes are running
ls -la /app             # what files are present
env                     # what env vars are set
```

## Endpoint Reference

| Path | Purpose | K8s Probe |
|---|---|---|
| `/api/health/live` | Liveness: is the process alive? | `livenessProbe` |
| `/api/health/ready` | Readiness: can it receive traffic? | `readinessProbe` |
| `/metrics` | Prometheus scrape target | Prometheus annotation |
| `/api/items` | Business logic: list items | — |
| `/api/items/:id` | Business logic: get item | — |

## Related Resources
- [Dockerfile](../../app/Dockerfile)
- [.dockerignore](../../app/.dockerignore)
- [K8s deployment probes guide](../kubernetes/probes-guide.md)
- [Phase 3: ECR push strategy](../eks/cluster-architecture.md)
