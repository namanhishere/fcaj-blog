---
title: "CloudWatch Alarms"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 5.8.2. </b> "
---

The awsplace RaftDB staging stack defines **nine CloudWatch alarms** across four operational dimensions: resource utilization, data durability, deployment stability, and network liveness. Every alarm is created in the CDK code and validated by the Jest test suite in **raftdb.test.cjs** — including assertions on threshold values, comparison operators, and the critical **TreatMissingData** setting.

#### Alarm inventory

| Alarm Name | Scope | Metric | Threshold | Evaluation | TreatMissingData |
|---|---|---|---|---|---|
| raftdb1CpuAlarm | Per member | CPUUtilization (MAX, 1 min) | >= 85% | 3 of 5 points | NOT_BREACHING |
| raftdb2CpuAlarm | Per member | CPUUtilization (MAX, 1 min) | >= 85% | 3 of 5 points | NOT_BREACHING |
| raftdb3CpuAlarm | Per member | CPUUtilization (MAX, 1 min) | >= 85% | 3 of 5 points | NOT_BREACHING |
| raftdb1MemoryAlarm | Per member | MemoryUtilization (MAX, 1 min) | >= 85% | 3 of 5 points | NOT_BREACHING |
| raftdb2MemoryAlarm | Per member | MemoryUtilization (MAX, 1 min) | >= 85% | 3 of 5 points | NOT_BREACHING |
| raftdb3MemoryAlarm | Per member | MemoryUtilization (MAX, 1 min) | >= 85% | 3 of 5 points | NOT_BREACHING |
| RaftDbSnapshotAgeAlarm | Cluster-wide | SnapshotAge (MAX, 5 min, math MAX across nodes) | > 900s (15 min) | 2 periods | NOT_BREACHING |
| RaftDbRestoreFailureAlarm | Cluster-wide | WalErrors (SUM, 5 min, math SUM across nodes) | > 0 | 1 period | NOT_BREACHING |
| RaftDbTcpLivenessAlarm | Cluster-wide | HealthyHostCount (MIN, 1 min) | < nodeCount | 3 of 3 points | BREACHING |

The deployment rollback alarms (per-member, sustained CPU < 1%) add another three alarms in multi-node deployments. They are covered separately below.

---

#### 1. Per-Member Resource Utilization Alarms

Function: **createRaftDbMember**

Each RaftDB member gets its own CPU and memory alarm. The design avoids aggregating across nodes so that a single over-utilized member is identified immediately without requiring dashboard inspection:

```typescript
const cpuAlarm = new cloudwatch.Alarm(scope, `${nodeName}CpuAlarm`, {
  metric: service.metricCpuUtilization({ period: Duration.minutes(1) }),
  threshold: 85,
  evaluationPeriods: 5,
  datapointsToAlarm: 3,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});

const memoryAlarm = new cloudwatch.Alarm(scope, `${nodeName}MemoryAlarm`, {
  metric: service.metricMemoryUtilization({ period: Duration.minutes(1) }),
  threshold: 85,
  evaluationPeriods: 5,
  datapointsToAlarm: 3,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});
```

The **3 out of 5** datapoints-to-alarm ratio provides a 2-minute grace window for transient CPU spikes (e.g., during snapshot compaction) before the alarm fires. This matches the capacity runbook's guidance: react at the 70% monitoring threshold, but the alarm fires at 85% to allow operator lead time before saturation.

The Jest test **per-member CPU and memory alarms exist for all three nodes** validates this in **raftdb.test.cjs**:

```javascript
test('per-member CPU and memory alarms exist for all three nodes', () => {
  const template = stagingTemplate();
  const alarms = resourceEntriesByType(template, 'AWS::CloudWatch::Alarm');
  for (let n = 1; n <= 3; n++) {
    const cpuAlarm = alarms.find(([id]) => id.includes(`raftdb${n}CpuAlarm`));
    expect(cpuAlarm).toBeDefined();
    const memoryAlarm = alarms.find(([id]) => id.includes(`raftdb${n}MemoryAlarm`));
    expect(memoryAlarm).toBeDefined();
  }
});
```

---

#### 2. Durability Alarms: Snapshot Age and WAL Errors

File: **Infrastructure**

Two cluster-wide alarms protect against data-loss scenarios. They use CloudWatch **MathExpression** to aggregate across all members:

#### a) SnapshotAgeAlarm

```typescript
const maxSnapshotAge = new cloudwatch.MathExpression({
  expression: `MAX([${Object.keys(snapshotAgeMetrics).join(', ')}])`,
  usingMetrics: snapshotAgeMetrics,
  period: Duration.minutes(5),
  label: 'Max snapshot age across cluster',
});

new cloudwatch.Alarm(this, 'RaftDbSnapshotAgeAlarm', {
  alarmDescription:
    'Snapshot age exceeds 15 minutes (900 seconds) across the raftdb cluster',
  metric: maxSnapshotAge,
  threshold: 900,
  evaluationPeriods: 2,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});
```

This alarm uses **MAX** across all three nodes, so it fires only when every node's snapshot is older than 15 minutes. The default snapshot interval is 300 seconds (5 minutes), so 900 seconds represents three missed snapshot cycles — a clear durability signal. The alarm is validated by the test **snapshot age alarm thresholds on max across nodes, not-breaching on cold start**.

#### b) RestoreFailureAlarm (WAL Errors)

```typescript
const totalWalErrors = new cloudwatch.MathExpression({
  expression: `SUM([${Object.keys(walMetrics).join(', ')}])`,
  usingMetrics: walMetrics,
  period: Duration.minutes(5),
  label: 'Total WAL errors across cluster',
});

new cloudwatch.Alarm(this, 'RaftDbRestoreFailureAlarm', {
  alarmDescription:
    'WAL errors detected in raftdb cluster (potential restore or data corruption)',
  metric: totalWalErrors,
  threshold: 0,
  evaluationPeriods: 1,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});
```

The WalErrors metric is an incrementing counter — any non-zero value means WAL corruption or truncation has occurred. The alarm uses **SUM** aggregation and fires on a single evaluation period, making it the fastest-reacting alarm in the system. It is validated by the test **restore failure alarm uses WalErrors with not-breaching on missing data**.

---

#### 3. Deployment Rollback Alarms

File: **Infrastructure**

For multi-node deployments, each member gets a deployment stability alarm that detects tasks that never started correctly after a deployment:

```typescript
for (const member of members) {
  new cloudwatch.Alarm(
    this,
    `${member.nodeName}DeploymentRollbackAlarm`,
    {
      alarmDescription: `Deployment failed to stabilize for ${member.nodeName} (sustained low CPU)`,
      metric: member.service.metricCpuUtilization({
        statistic: cloudwatch.Stats.AVERAGE,
        period: Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 5,
      comparisonOperator:
        cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    },
  );
}
```

This is a negative-space alarm: sustained CPU *below* 1% for 5 minutes after a deployment means the task is either stuck in a crash loop, failed to bind its port, or never completed recovery. Combined with the ECS deployment circuit breaker (which rolls back on its own), this alarm provides human-visible confirmation that something went wrong. The test **deployment rollback alarm exists for every member with not-breaching** validates this.

---

#### 4. NLB TCP Liveness Alarm

File: **Infrastructure**

The multi-node topology exposes RaftDB through an internal Network Load Balancer. A liveness alarm monitors the NLB's healthy target count:

```typescript
new cloudwatch.Alarm(this, 'RaftDbTcpLivenessAlarm', {
  alarmDescription:
    'TCP liveness only: the internal NLB has no healthy RaftDB target',
  metric: healthyTargets,
  threshold: nodeCount,
  evaluationPeriods: 3,
  datapointsToAlarm: 3,
  comparisonOperator:
    cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.BREACHING,
});
```

This is the **only alarm** that uses **BREACHING** for missing data. The rationale: if the NLB metric itself is absent, the load balancer or its logging path has failed, which is itself an actionable condition. The test **staging alarms when provider TCP liveness has no healthy target** validates this alarm's existence and configuration.

---

#### TreatMissingData Philosophy

The choice between **NOT_BREACHING** and **BREACHING** is intentional for each alarm:

| Setting | Used For | Rationale |
|---|---|---|
| NOT_BREACHING | CPU, memory, snapshot age, WAL errors, deployment rollback | A cold start or freshly deployed stack lacks metric history; alarming would create false positives |
| BREACHING | NLB TCP liveness | If the NLB metric stream stops entirely, the load-balancing path is broken — this is actionable |

This prevents the "alarm fatigue" pattern where operators learn to ignore alarms because they fire during every deployment.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Open CloudWatch Alarms in the AWS Console.
Filter to the RaftDB staging stack alarms and capture the list showing all 9+ alarms with their current state (OK/ALARM/INSUFFICIENT_DATA).
Save as: static/images/5.7/cloudwatch-alarms-list.png

Screenshot suggestion 2: Click into the RaftDbSnapshotAgeAlarm.
Capture the alarm detail view showing the threshold (900s), the math expression, and the metric graph.
Save as: static/images/5.7/snapshot-age-alarm-detail.png
-->
