# Local Development Guide

## What It Is
How to run the full devops-capstone stack locally using Docker Compose.

## Quick Start

```bash
cd devops-capstone/app

# Start everything (app + postgres)
docker compose up --build

# Background mode
docker compose up -d --build

# View logs
docker compose logs -f app
docker compose logs -f postgres

# Stop
docker compose down

# Stop AND delete volumes (wipes database)
docker compose down -v
```

## Endpoints (Local)

| URL | What you get |
|---|---|
| `http://localhost:3000/api/items` | List all items |
| `http://localhost:3000/api/items/1` | Get item by ID |
| `http://localhost:3000/api/health/live` | Liveness probe response |
| `http://localhost:3000/api/health/ready` | Readiness probe response |
| `http://localhost:3000/metrics` | Prometheus metrics |

## Key: Service Discovery via Service Name

The app connects to Postgres using `DATABASE_URL=postgresql://devops:devops_password@postgres:5432/devops_db`.

Notice the hostname is `postgres` — not `localhost`.

This is because **containers communicate by service name**, not by localhost.
Each Docker Compose service has its own network namespace.
The `capstone-network` bridge network enables DNS resolution between services.

**This is the exact same model used in Kubernetes:**
- In docker-compose: service name → DNS within the `capstone-network` bridge
- In K8s: pod reaches another pod via a `Service` object → resolved by kube-dns

If you try `localhost` inside the app container, it resolves to the app container
itself — not to the postgres container.

## Health Check Dependency

```yaml
depends_on:
  postgres:
    condition: service_healthy
```

The app won't start until postgres is healthy.
Postgres marks itself healthy when `pg_isready` succeeds.
Without this: app starts before DB is ready → connection error → app crashes → CrashLoopBackOff.

This is the same problem you'll see in EKS when pod start order isn't managed.
K8s solution: `initContainers` that wait for DB, or readiness probes.

## Changing Source Code

Source is mounted as a volume in the dev target:
```yaml
volumes:
  - ./src:/app/src:ro
```

Changes trigger hot reload via NestJS watch mode.
In production (the `runner` Docker target), there's no volume mount.
The compiled `/dist` is baked into the image at build time.

## Connecting to Postgres Directly

```bash
# Connect from your host machine
psql -h localhost -p 5432 -U devops -d devops_db
# Password: devops_password

# Or from inside the postgres container
docker exec -it devops-capstone-postgres psql -U devops -d devops_db
```
