---
title : "RaftDB Infrastructure & Route 53"
date : 2024-01-01
weight : 8
chapter : false
pre : " <b> 5.3.8 </b> "
---

The final two modules provide the DNS/TLS foundation for the split-domain architecture and the **RaftDB staging infrastructure** — an optional second CloudFormation stack used for qualification, recovery drills, and member replacement practice.

#### Module overview

| Module | File | Resources | Purpose |
|---|---|---|---|
| Route 53 & ACM | **Infrastructure** | Imported hosted zone, ACM wildcard certificate | DNS + TLS for **api.** and **ws.** subdomains |
| RaftDB Staging Stack | **Infrastructure** | ECS cluster, NLB, Cloud Map, EFS, S3, CloudWatch dashboard | Disposable environment for RaftDB qualification |
| RaftDB Cluster Factory | **Infrastructure** | Factory functions (no resources directly) | Reusable **createRaftDbCluster()** + **createRaftDbMember()** |
| CloudWatch Dashboard | **Infrastructure** | CloudWatch dashboard widgets | Raft consensus monitoring |

---

#### 1. Route 53 & ACM Certificate

The Route 53 module imports an existing hosted zone and creates a wildcard ACM certificate covering all subdomains.

```typescript
export function createRoute53AndCertificates(
  scope: Construct,
  input: Route53AndCertInput
): Route53AndCertOutput {
  const { domainName, hostedZoneId } = input;

  // Import existing hosted zone (must exist before deployment)
  const hostedZone = route53.HostedZone.fromHostedZoneAttributes(
    scope, 'HostedZone',
    { hostedZoneId, zoneName: domainName }
  );

  // Wildcard certificate covering *.domainName
  const wildcardCert = new acm.Certificate(scope, 'WildcardCertificate', {
    domainName: `*.${domainName}`,
    validation: acm.CertificateValidation.fromDns(hostedZone),
  });

  return { hostedZone, wildcardCert };
}
```

#### a) Certificate consumers

The wildcard certificate is used by two modules:

| Module | Domain | Protocol | Port |
|---|---|---|---|
| **API Gateway** (**Infrastructure**) | **api.domain.com** | HTTPS | 443 |
| **ECS ALB** (**Infrastructure**) | **ws.domain.com** | HTTPS | 443 |

**Separate TLS for Amplify:** The root domain (**domain.com**) has its TLS managed by Amplify Hosting — Amplify provisions and manages its own ACM certificate. The wildcard certificate only covers subdomains.

#### b) Why import the hosted zone?

```typescript
route53.HostedZone.fromHostedZoneAttributes(scope, 'HostedZone', {
  hostedZoneId,
  zoneName: domainName,
});
```

The hosted zone is **imported**, not created by CDK. It must exist before the first deployment. This is common for production domains where the hosted zone is created manually or by a separate bootstrap stack. The CDK stack only creates DNS **records** within the existing zone — it never creates or deletes the zone itself.

#### c) DNS validation

```typescript
validation: acm.CertificateValidation.fromDns(hostedZone)
```

CDK uses **DNS validation** (not email validation) for the ACM certificate. It automatically creates the required **_validation** CNAME records in the hosted zone, waits for them to propagate, and cleans them up after validation completes. This means certificate renewal is fully automated — ACM re-validates before expiry without manual intervention.

---

#### 2. RaftDB Staging Stack

The **RaftDbStagingStack** is an **optional second CloudFormation stack** created when **ENABLE_RAFTDB=true**. It provides a disposable, isolated environment for RaftDB qualification, recovery drills, and member replacement practice.

**This stack is NEVER used in production.** The production RaftDB runs as a sidecar in the main ECS task (see [5.3.4 ECS Compute](5.3.4-ecs-compute/)).

#### a) Stack creation (conditional)

```typescript
if (process.env.ENABLE_RAFTDB === 'true') {
  const stagingStack = new RaftDbStagingStack(app, 'RaftDbStagingStack', {
    env,
    imageDigest: process.env.RAFTDB_IMAGE_DIGEST,
    dataGeneration: process.env.RAFTDB_DATA_GENERATION,
    restoreFromS3: parseRestoreFromS3(process.env.RAFTDB_RESTORE_FROM_S3),
    nodeCount: parseNodeCount(process.env.RAFTDB_NODE_COUNT),
  });
  stagingStack.addDependency(mainStack,
    'RaftDB staging imports the shared ECR repository');
}
```

#### b) Stack configuration parameters

| Parameter | Default | Valid Values | Purpose |
|---|---|---|---|
| **imageDigest** | Required | **sha256:<64 hex chars>** | Immutable RaftDB image to qualify |
| **dataGeneration** | **staging-1** | Lowercase slug, 1–63 chars | EFS path generation (**/raftdb/<gen>/member-N**); change to get a fresh WAL |
| **restoreFromS3** | **false** | **"true"** or **"false"** | Whether to restore from S3 snapshot; requires **dataGeneration** starting with **restore-** |
| **nodeCount** | **1** | **1** or **3** | Single-node qualification or 3-node full Raft cluster qualification |

#### c) VPC configuration by node count

| Node Count | Subnet Type | AZs | Access Pattern |
|---|---|---|---|
| **1** (single-node) | **PUBLIC** | 1 AZ | Direct TCP 9100 from **0.0.0.0/0** (qualification tooling) |
| **3** (three-node) | **PRIVATE_ISOLATED** | 3 AZs | Internal only — Raft peer-to-peer on TCP 9101 |

The single-node mode opens port 9100 to the internet for qualification tests. The three-node mode is fully isolated — only Raft peer traffic on port 9101, no public access.

![RaftDB Staging Architecture Diagram](/images/5-Workshop/5.3-CDK-Project-Structure/raftdb-staging.png)

#### d) Staging stack resources

| Resource | Type | Purpose |
|---|---|---|
| **ECS Cluster** | Fargate | Runs RaftDB staging tasks |
| **NLB** | Network Load Balancer (multi-node only) | TCP load balancing on port 9100 |
| **Cloud Map Namespace** | **HTTP_NAMESPACE** | Service discovery for RaftDB peer discovery |
| **EFS FileSystem** | Encrypted NFS | Durable WAL per member |
| **EFS Access Points** | One per member | POSIX enforcement (UID/GID 10001:10001) |
| **S3 Snapshot Bucket** | Versioned, 35-day noncurrent retention | Periodic RaftDB snapshots |
| **CloudWatch Dashboard** | Custom metrics widgets | Raft consensus monitoring |
| **Security Groups** | Per-member + client SG | Peer-to-peer TCP 9101 + client TCP 9100 |

#### e) Monitoring: CloudWatch alarms and dashboard

| Alarm | Metric | Threshold | Severity |
|---|---|---|---|
| **Snapshot Age** | **MAX(SnapshotAge)** across cluster | > 15 minutes (900s) | Warning — snapshots are stale |
| **WAL Errors** | **SUM(WalErrors)** across cluster | > 0 | Critical — WAL corruption |
| **Deployment Stability** | Per-service CPU utilization | < 1% for 5 periods | Info — verifies idle after deployment |
| **NLB Liveness** | **HealthyHostCount** | < node count for 3 periods | Critical — members are unreachable |

The CloudWatch dashboard (**Infrastructure**) adds Raft-specific widget groups:

```
Dashboard Widgets
├── Raft State       → Leader/Follower/Candidate transitions per member
├── Log Replication  → Applied index, commit index, last log index
├── Snapshots        → Snapshot age, size, count
├── Network          → RUDP retransmissions, TCP connection count
└── WAL              → WAL errors, bytes written, segment count
```

These custom metrics are emitted by the RaftDB C++ process and provide deep visibility into Raft consensus health — essential for qualification and recovery drills.

#### f) Member replacement procedure

The staging stack is designed to support the documented member replacement procedure:

```
Step 1: REMOVE  → Remove old member from Raft configuration
                  (committed membership change via raftdb-cli)

Step 2: STOP    → Stop old ECS task (desiredCount=0)

Step 3: PROVISION → Bump dataGeneration (e.g., staging-1 → staging-2)
                    Creates fresh EFS access point → clean WAL

Step 4: START   → Start replacement task (desiredCount=1)
                  Empty WAL, clean catalog

Step 5: INSTALL → Pull snapshot + WAL tail from a healthy peer

Step 6: ADD     → Add member back to Raft cluster

Step 7: VERIFY  → Confirm quorum reached + applied index converged
```

**Safety rules enforced by process:**
- **Never remove two voters at once** — would cause loss of quorum and cluster unavailability
- **Never reuse a member ID** while another task with that ID could still run
- **Emergency quorum changes require written approval + verified backup**
- **dataGeneration** must change on every replacement** — prevents accidental WAL reuse

---

#### 3. RaftDB Cluster Factory

The **Infrastructure** module provides reusable factory functions for creating RaftDB clusters:

| Function | Purpose |
|---|---|
| **createRaftDbCluster(props)** | Creates shared infrastructure: ECS cluster, NLB, Cloud Map namespace, EFS, S3 snapshot bucket, CloudWatch dashboard |
| **createRaftDbMember(props)** | Creates per-member resources: EFS access point, ECS Fargate service, task definition, security group |

These factories are used by the staging stack and can be composed for production multi-node deployments if needed. The factory pattern keeps the staging logic testable — the raftdb contract tests synthesize templates with different cluster configurations (1-member, 3-member, restore mode) and validate the generated CloudFormation.

---

#### 4. Complete Infrastructure Diagram

Here is the complete infrastructure deployed by the CDK stacks:

```
┌────────────────────────────────────────────────────────────────────┐
│  Route 53 Hosted Zone (domain.com)                                 │
│  ├── domain.com          → Amplify (managed TLS)                   │
│  ├── api.domain.com      → API Gateway (wildcard cert)             │
│  └── ws.domain.com       → ALB (wildcard cert)                     │
│                                                                    │
│  ACM Wildcard Certificate (*.domain.com)                           │
│  ├── api.domain.com (API Gateway custom domain)                    │
│  └── ws.domain.com  (ALB HTTPS listener)                           │
│                                                                    │
│  VPC (2 AZs, public subnets only, no NAT Gateway)                  │
│  ├── ALB (internet-facing, HTTPS 443 → ECS:8980)                   │
│  │   ├── Health check: GET /health (30s interval)                  │
│  │   └── Idle timeout: 3600s (WebSocket support)                   │
│  ├── ECS Fargate (1 task: 1024 CPU / 2048 MiB)                     │
│  │   ├── RaftDB sidecar (:9100, non-root 10001)                    │
│  │   │   └── EFS mount: /data/raftdb (encrypted)                   │
│  │   └── Go App (:8980)                                            │
│  │       └── depends_on: RaftDB HEALTHY                            │
│  └── Security Groups:                                              │
│      ├── ALB SG: 0.0.0.0/0 → :80, :443                             │
│      └── ECS SG: ALB SG → :8980                                    │
│                                                                    │
│  DynamoDB (4 tables, on-demand billing, composite PK/SK)           │
│  ├── Config (PK=CONFIG, SK=SINGLETON)                              │
│  ├── Bans (PK=BAN#type#id, SK=BAN)                                 │
│  ├── Milestones (PK=MILESTONE, GSI: TriggerAtIndex)                │
│  └── History (PK=HISTORY, GSI: XOriginalIndex)                     │
│                                                                    │
│  S3 Buckets                                                        │
│  ├── awsplace-canvas-{account} (versioned, canvas binary, 32 MiB)  │
│  ├── awsplace-exports-{account} (PNG exports)                      │
│  └── RaftDB snapshots (versioned, 35-day retention)                │
│                                                                    │
│  ECR Repository (awsplace-ecs, keep 10 images, raftdb-* immutable) │
│                                                                    │
│  Lambda (Node.js 24, 512 MB, 30s timeout, NO VPC)                  │
│  └── API Gateway HTTP API v2 ($default → Lambda)                   │
│                                                                    │
│  Amplify Hosting (manual zip deploy, SPA rewrite + /admin.html)    │
│                                                                    │
│  Secrets Manager: awsplace/app-secrets (SESSION_SECRET, etc.)      │
│                                                                    │
│  IAM Roles (3 roles, least-privilege scoped)                       │
│  ├── ECS Task Execution (ECR pull + CW Logs + Secrets Manager)     │
│  ├── ECS Task (DynamoDB CRUD + S3 R/W + EFS mount)                 │
│  └── Lambda Execution (DynamoDB CRUD + S3 PutObject + CW Logs)     │
│                                                                    │
│  [Optional: RaftDbStagingStack — ENABLE_RAFTDB=true]               │
│  ├── Separate VPC (1 AZ or 3 AZs)                                  │
│  ├── ECS Cluster + NLB + Cloud Map                                 │
│  ├── EFS + S3 (per-member storage)                                 │
│  └── CloudWatch Dashboard + Alarms                                 │
└────────────────────────────────────────────────────────────────────┘
```

