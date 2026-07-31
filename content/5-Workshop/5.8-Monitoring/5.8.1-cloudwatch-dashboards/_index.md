---
title: "CloudWatch Dashboards"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.8.1. </b> "
---

The awsplace CDK codebase provisions two CloudWatch dashboards — a **RaftDB staging dashboard** in the RaftDbStagingStack and a **production RaftDB sidecar dashboard** created through shared infrastructure functions. All dashboard widgets are defined in the files **Infrastructure** and **Infrastructure** inside the **cdk/lib/** directory. The Jest test suite validates that every planned metric appears in the dashboard body.

#### Dashboard overview

| Dashboard | Scope | Source File | Key Widgets |
|---|---|---|---|
| RaftDbDashboard | Staging cluster (3-node Raft) | createRaftDbCluster | EFS I/O limit, burst credits, ECS utilization per member, NLB target health, Raft consensus panels |
| Production Raft sidecar | Application stack (1-node sidecar) | createRaftDbApplicationStorage | EFS provider signals |

All dashboards are emitted as CloudFormation outputs (**RaftDbDashboardName**), so the dashboard name is discoverable from the stack outputs without opening the AWS Console.

---

#### 1. EFS Provider Signal Widgets

Function: **createRaftDbCluster**

Every RaftDB cluster dashboard starts with an EFS health row that displays:

| Metric | Namespace | Statistic | Period | What It Means |
|---|---|---|---|---|
| PercentIOLimit | AWS/EFS | MAXIMUM | 1 min | How close the file system is to its I/O throughput limit |
| ClientConnections | AWS/EFS | AVERAGE | 1 min | Number of NFS client connections from ECS tasks |
| BurstCreditBalance | AWS/EFS | MINIMUM | 5 min | Remaining burst credits before throughput throttling |

```typescript
dashboard.addWidgets(
  new cloudwatch.GraphWidget({
    title: 'RaftDB EFS provider signals',
    left: [
      new cloudwatch.Metric({
        namespace: 'AWS/EFS',
        metricName: 'PercentIOLimit',
        dimensionsMap: efsDimensions,
        statistic: cloudwatch.Stats.MAXIMUM,
        period: Duration.minutes(1),
        label: 'I/O limit %',
      }),
      new cloudwatch.Metric({
        namespace: 'AWS/EFS',
        metricName: 'ClientConnections',
        dimensionsMap: efsDimensions,
        statistic: cloudwatch.Stats.AVERAGE,
        period: Duration.minutes(1),
        label: 'Client connections',
      }),
    ],
    right: [
      new cloudwatch.Metric({
        namespace: 'AWS/EFS',
        metricName: 'BurstCreditBalance',
        dimensionsMap: efsDimensions,
        statistic: cloudwatch.Stats.MINIMUM,
        period: Duration.minutes(5),
        label: 'Burst credits',
      }),
    ],
    leftYAxis: { min: 0 },
    rightYAxis: { min: 0 },
  }),
);
```

The dual-Y-axis design separates rate metrics (left) from accumulated credits (right), preventing the burst-credit scale from flattening the I/O-limit line.

---

#### 2. Raft Consensus Custom-Metric Widgets

Function: **addRaftConsensusWidgets**

The RaftDB runtime emits custom CloudWatch metrics under the **RaftDb** namespace with **Cluster** and **NodeId** dimensions. These metrics are defined in the planned emission contract and are rendered on the dashboard via four dedicated widgets:

| Widget Title | Metrics Displayed | Height | Operational Question |
|---|---|---|---|
| Raft consensus: leader, term, quorum | LeaderId, Term, QuorumStatus (per node, MAX, 1 min) | 6 | Who is the leader? Is quorum maintained? |
| Raft replication lag | ReplicationLag (per node, MAX, 1 min) | 5 | Are any followers falling behind the leader? |
| Raft commit index vs applied index | CommitIndex, AppliedIndex (per node, MAX, 1 min) | 5 | Is the state machine keeping up with the log? |
| Raft durability: snapshot age, WAL errors, membership | SnapshotAge (MAX, 5 min), WalErrors (SUM, 5 min), MembershipChanges (MAX, 5 min) | 5 | Is durable storage healthy? Are snapshots recent? |

The metric contract is defined as a typed interface in infrastructure code:

```typescript
interface RaftMetricProps {
  readonly metricName: string;
  readonly label: string;
  readonly statistic: string;
  readonly period: Duration;
  readonly unit?: cloudwatch.Unit;
}
```

Each metric is instantiated per node, producing a comprehensive multi-node view. The full list of custom metrics includes:

- **LeaderId** (Count) — current leader node ID; 0 means not leader
- **Term** (Count) — monotonic Raft term
- **ReplicationLag** (Count) — log entries behind the leader
- **CommitIndex** (Count) — highest log entry known to be committed
- **AppliedIndex** (Count) — highest log entry applied to the state machine
- **QuorumStatus** (Count) — 1 = quorum, 0 = lost quorum
- **SnapshotAge** (Seconds) — seconds since last durable snapshot
- **WalErrors** (Count) — incrementing WAL corruption or truncation errors
- **MembershipChanges** (Count) — monotonic count of committed membership changes

All nine metrics are validated by the Jest test **staging dashboard includes RaftDb custom-metric panels for all 3 nodes** in **raftdb.test.cjs**.

---

#### 3. Per-Member ECS Utilization Widgets

Function: **createRaftDbMember**

Each RaftDB member gets a dedicated ECS utilization widget showing CPU and memory usage:

```typescript
dashboard.addWidgets(
  new cloudwatch.GraphWidget({
    title: `${nodeName} ECS utilization`,
    left: [
      service.metricCpuUtilization({
        period: Duration.minutes(1),
        statistic: cloudwatch.Stats.AVERAGE,
        label: 'CPU %',
      }),
      service.metricMemoryUtilization({
        period: Duration.minutes(1),
        statistic: cloudwatch.Stats.AVERAGE,
        label: 'Memory %',
      }),
    ],
    leftYAxis: { min: 0, max: 100 },
  }),
);
```

The Y-axis is clamped to 0–100% so that utilization changes are visually meaningful — a 5% CPU spike on a default 0–3% auto-scaled axis would otherwise be invisible. These widgets are co-located with the CPU and memory alarms that fire at 85% utilization.

---

#### 4. NLB Target TCP Liveness

For multi-node (3-member) deployments, an additional widget tracks the internal Network Load Balancer's healthy and unhealthy target counts:

```typescript
dashboard.addWidgets(
  new cloudwatch.GraphWidget({
    title: 'RaftDB target TCP liveness',
    left: [
      healthyTargets.with({ label: 'Healthy targets' }),
      unhealthyTargets.with({ label: 'Unhealthy targets' }),
    ],
    leftYAxis: { min: 0 },
  }),
);
```

This widget is paired with the **RaftDbTcpLivenessAlarm** that fires when healthy targets fall below the expected node count.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Open the CloudWatch Dashboards console in AWS.
Navigate to the RaftDB dashboard and capture the full view showing all widgets:
EFS signals, Raft consensus panels, per-member ECS utilization, and NLB liveness.
Save as: static/images/5.7/raftdb-dashboard.png

Screenshot suggestion 2: Select a single Raft consensus widget (e.g., "Raft consensus: leader, term, quorum").
Zoom into a time range where a leadership transition occurred to show the metric transitions.
Save as: static/images/5.7/raft-consensus-widget.png
-->
