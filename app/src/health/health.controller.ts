import { Controller, Get } from '@nestjs/common';
import {
  HealthCheck,
  HealthCheckService,
  MemoryHealthIndicator,
} from '@nestjs/terminus';

/**
 * Health Controller
 *
 * Exposes two endpoints used by Kubernetes probes:
 *
 * GET /health/live  → Liveness probe
 *   - Is the process alive and not deadlocked?
 *   - K8s will RESTART the pod if this fails.
 *   - Should be fast, no external dependencies.
 *   - Check: heap memory < 300MB
 *
 * GET /health/ready → Readiness probe
 *   - Is the app ready to receive traffic?
 *   - K8s will STOP ROUTING to the pod if this fails (no restart).
 *   - No restart — just removes pod from load balancer rotation.
 *   - Can check DB, cache — anything that makes the app functional.
 *
 * WHY SEPARATE?
 * If you use a single /health for both probes and the DB goes down,
 * K8s will restart your pod in an infinite loop — which doesn't fix the DB.
 * With separate probes, K8s just stops routing traffic and lets the pod live,
 * waiting for the DB to recover.
 */
@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private memory: MemoryHealthIndicator,
  ) {}

  /**
   * Liveness probe — only internal checks
   * Kubernetes calls this every 10s (configured in k8s/base/deployment.yaml)
   * Fast: no external I/O. If this fails, pod is RESTARTED.
   */
  @Get('live')
  @HealthCheck()
  liveness() {
    return this.health.check([
      // Restart if heap exceeds 300MB — indicates memory leak
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),
    ]);
  }

  /**
   * Readiness probe — checks if app can serve traffic
   * K8s calls this before routing traffic to the pod.
   * If this fails, pod is REMOVED from Service endpoints (not restarted).
   * Add DB health check here in Phase 3 when Postgres is wired in.
   */
  @Get('ready')
  @HealthCheck()
  readiness() {
    return this.health.check([
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),
      // TODO Phase 3: Add TypeORM/Prisma health indicator when DB is connected
      // () => this.db.pingCheck('postgres'),
    ]);
  }
}
