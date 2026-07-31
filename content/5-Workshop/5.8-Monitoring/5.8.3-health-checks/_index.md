---
title: "Container & Application Health Checks"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 5.8.3. </b> "
---

The awsplace project uses health checks at three layers — ECS container health, container dependency ordering, and ALB target group health — to ensure that only properly initialized services receive traffic. These health checks are defined in the CDK code in infrastructure code and **Infrastructure**, and their exact commands and parameters are enforced by the Jest contract tests.

#### Health check layers

| Layer | Mechanism | Defined In | Failure Behavior |
|---|---|---|---|
| RaftDB container | HEALTHCHECK command (**raftdb-healthcheck**) | Infrastructure | ECS restarts the container after 10 consecutive failures |
| Application container | DependsOn RaftDB container with **HEALTHY** condition | Infrastructure | App container does not start until RaftDB passes health checks |
| ALB target group | HTTP health probe on **/health** path | Infrastructure | ALB drains the target; ECS deployment circuit breaker may roll back |

---

#### 1. RaftDB Container Health Check

Function: **createRaftDbMember**

Every RaftDB container (both production sidecar and staging members) runs the same health command:

```typescript
healthCheck: {
  command: ['CMD', '/usr/local/bin/raftdb-healthcheck'],
  interval: Duration.seconds(5),
  timeout: Duration.seconds(3),
  retries: 10,
  startPeriod: Duration.seconds(15),
},
```

This health check is governed by the **runtime contract** defined in **docs/raftdb/runtime-contract.md**. The contract specifies:

| Property | Value | Rationale |
|---|---|---|
| **Interval** | 5 seconds | Fast detection: a failed node is detected within 50 seconds (10 retries × 5s) |
| **Timeout** | 3 seconds | The health check is lightweight — it only validates the readiness marker, creates a probe file, opens the port, then removes the probe |
| **Retries** | 10 | Allows temporary resource contention (e.g., EFS burst-credit exhaustion) to resolve without restarting |
| **Start period** | 15 seconds | Recovery (snapshot restore + WAL replay) may take several seconds; the grace period prevents premature failure |

The **raftdb-healthcheck** binary validates three conditions before reporting success:

1. **Readiness marker present** — The server atomically publishes a nonempty file at **/tmp/raftdb-ready** only after local or S3 recovery completes successfully. If the marker is absent, recovery is still in progress or has failed.
2. **Durable mount writable** — The health check creates, writes, and removes a temporary probe file below **RAFTDB_DATA_DIR** to confirm the EFS access point is mounted and writable.
3. **Client port open** — The health check opens a TCP connection to the local client port (**9100**) to confirm the listener is accepting connections.

Before recovery starts, the server removes any stale readiness marker from a previous run. A stale process marker, read-only or unavailable durable mount, incomplete recovery, or closed listener all result in a failed health check, which ECS treats as a non-healthy container.

The Jest test validates the exact health check command in **raftdb.test.cjs**:

```javascript
expect(container.HealthCheck.Command).toEqual([
  'CMD',
  '/usr/local/bin/raftdb-healthcheck',
]);
```

---

#### 2. Container Dependency Ordering

Function: **createEcs**

The application container depends on the RaftDB sidecar reaching a healthy state before it starts:

```typescript
appContainer.addContainerDependencies({
  container: raftDbContainer,
  condition: ecs.ContainerDependencyCondition.HEALTHY,
});
```

This dependency is validated by the test **application runs exclusively against its healthy raftdb sidecar** in **raftdb.test.cjs**:

```javascript
expect(app.DependsOn).toContainEqual({ ContainerName: 'RaftDb', Condition: 'HEALTHY' });
```

Without this ordering guarantee, the application container could start before the RaftDB sidecar has finished recovery, causing every initial request to fail. The **HEALTHY** condition is the strongest available — it requires all three health check validations (readiness marker, writable mount, open port) to pass before the dependency is satisfied.

For RaftDB staging members, there is no equivalent dependency because each member is an independent ECS service. The NLB health check provides the equivalent gating function.

---

#### 3. ALB Target Group Health Check

Function: **createEcs**

The production Application Load Balancer validates application health via an HTTP endpoint:

```typescript
healthCheck: {
  path: '/health',
  interval: Duration.seconds(30),
  timeout: Duration.seconds(5),
  healthyThresholdCount: 2,
},
```

This is a standard HTTP health probe at the application layer:

| Property | Value | Rationale |
|---|---|---|
| **Path** | /health | A dedicated health endpoint that returns 200 OK when the application is ready |
| **Interval** | 30 seconds | Application-level health changes more slowly than container-level; 30s avoids unnecessary probe traffic |
| **Timeout** | 5 seconds | The /health handler is lightweight; 5s is generous for a single health check under load |
| **Healthy threshold** | 2 | Requires two consecutive successes before the target is placed back in service |

The ALB health check works with the **DeploymentCircuitBreaker** to provide defense-in-depth during deployments:

```typescript
cfnService.addPropertyOverride('DeploymentConfiguration.DeploymentCircuitBreaker', {
  Enable: true,
  Rollback: true,
});
```

If a new task fails ALB health checks, the circuit breaker rolls back the deployment automatically. The deployment rollback alarm (covered in 5.7.2) provides a human-visible confirmation that this occurred.

---

#### 4. Readiness Marker Contract

The readiness marker at **/tmp/raftdb-ready** is the linchpin of the health-check system. The marker lifecycle is defined in the runtime contract:

1. **Before recovery**: The server removes any stale marker from a previous process.
2. **After recovery succeeds**: The server atomically publishes a nonempty marker, *then* opens the client port. The ordering is critical — a port that accepts connections before recovery completes would serve inconsistent data.
3. **During shutdown**: The server removes the marker as shutdown begins, causing health checks to fail and ECS to drain connections before the process exits.

This contract means the health check provides a truthful signal: if the marker exists, the server has completed recovery, has a writable durable store, and is ready to serve client requests.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Open the ECS console, navigate to a RaftDB task, and view the "Health" tab or the container details showing the health check configuration and last status.
Save as: static/images/5.7/ecs-health-check.png

Screenshot suggestion 2: Open the EC2 Target Groups console, select the ECS target group, and capture the "Health checks" tab showing the /health path, interval, timeout, and threshold settings.
Save as: static/images/5.7/alb-target-health.png
-->
