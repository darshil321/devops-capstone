# =============================================================================
# STAGE 1: Dependencies
# =============================================================================
# WHY: We separate dependency installation into its own stage so Docker can
# cache the node_modules layer. If only source code changes (not package.json),
# Docker reuses this cached layer and skips npm install entirely.
# LAYER CACHE LESSON: Docker rebuilds a layer and ALL subsequent layers when
# ANY file in that layer changes. So we COPY package*.json BEFORE copying src/.
# =============================================================================
FROM node:20-alpine AS deps

WORKDIR /app

# Copy ONLY the dependency manifests first.
# This layer is cached as long as package.json and package-lock.json don't change.
# Changing a .ts file will NOT invalidate this cache.
COPY package.json package-lock.json ./

# Install ALL deps including devDependencies (needed to compile TypeScript)
# --frozen-lockfile ensures reproducible builds (CI-safe)
RUN npm ci --frozen-lockfile


# =============================================================================
# STAGE 2: Builder
# =============================================================================
# WHY: We compile TypeScript to JavaScript here. This stage produces the /dist
# folder. We need devDependencies (like typescript, ts-node) to compile — but
# we do NOT want them in the final image. That's why we have separate stages.
# =============================================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy installed deps from the deps stage (includes devDeps for tsc)
COPY --from=deps /app/node_modules ./node_modules

# NOW copy source code. If only source changes, Docker restores node_modules
# from the deps stage cache and only reruns this COPY + RUN build step.
COPY . .

# Compile TypeScript → JavaScript
RUN npm run build


# =============================================================================
# STAGE 3: Production Runner
# =============================================================================
# WHY: This is the image that actually runs in EKS. It contains ONLY:
#   - node:20-alpine base (~50MB, not ~900MB for full node)
#   - Production node_modules only (no typescript, jest, eslint, etc.)
#   - The compiled /dist output
#
# Result: final image is ~150MB instead of ~800MB
# This matters for: ECR storage costs, image pull time, attack surface
# =============================================================================
FROM node:20-alpine AS runner

# Security: do not run as root inside the container
# WHY: If an attacker gets code execution inside the pod, they don't get root.
# This is a container security baseline requirement.
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nestjs -u 1001

WORKDIR /app

# Copy only production deps from deps stage
# We re-run npm ci --omit=dev to strip devDependencies
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile --omit=dev && npm cache clean --force

# Copy compiled output from builder stage
COPY --from=builder /app/dist ./dist

# Switch to non-root user
USER nestjs

# Expose the app port
EXPOSE 3000

# Health check so Docker itself knows if the container is healthy
# (separate from K8s probes — Docker uses this for docker-compose health)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:3000/health/live || exit 1

# Start the compiled app (not ts-node — that's dev only)
CMD ["node", "dist/main.js"]
