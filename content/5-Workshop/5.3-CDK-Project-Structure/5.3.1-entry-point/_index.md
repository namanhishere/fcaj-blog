---
title : "Entry Point & Stack Composition"
date : 2024-01-01
weight : 1
chapter : false
pre : " <b> 5.3.1 </b> "
---

The CDK application begins at a single entry point file (**bin/**) that creates the CDK **App**, parses and validates environment variables for deployment configuration, instantiates the main **AwsplaceStack**, and conditionally adds a **RaftDbStagingStack**. This file is the bridge between CI/CD pipelines and the infrastructure code.

#### Entry point responsibilities

| Responsibility | Description |
|---|---|
| Environment configuration | Sets AWS account and region (default **ap-southeast-1**) |
| Input validation | 5 parsing functions validate deployment inputs before they reach any stack |
| Stack instantiation | Creates **AwsplaceStack** with validated props |
| Conditional staging | Creates **RaftDbStagingStack** only when **ENABLE_RAFTDB=true** |
| Cross-stack dependency | Staging stack depends on main stack (shared ECR repository) |

---

#### 1. Entry Point Code

```typescript
const app = new App();
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'ap-southeast-1',
};

const mainStack = new AwsplaceStack(app, 'AwsplaceStack', {
  env,
  domainName: process.env.DOMAIN_NAME || 'place.namanhishere.com',
  hostedZoneId: parseHostedZoneId(process.env.HOSTED_ZONE_ID),
  ecsImageTag: parseEcsImageTag(process.env.ECS_IMAGE_TAG),
  raftDbImageDigest: parseRaftDbImageDigest(process.env.RAFTDB_IMAGE_DIGEST),
});

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

app.synth();
```

![CDK Entry Point Flow](/images/5-Workshop/5.3-CDK-Project-Structure/entry-point-flow.png)

---

#### 2. Input Validation Functions

Five parsing functions guard the boundary between the outside world (environment variables set by CI/CD) and the CDK internals. Each validates format and provides a deterministic fallback for credential-free synthesis.

#### a) **parseHostedZoneId()**

```typescript
function parseHostedZoneId(raw: string | undefined): string {
  if (!raw) {
    // Deterministic placeholder for credential-free synthesis
    return 'ZPLACEHOLDERPLACEHOLDER';
  }
  if (!/^Z[A-Z0-9]+$/.test(raw)) {
    throw new Error(
      'HOSTED_ZONE_ID must be a Route 53 hosted zone ID (starts with Z, alphanumeric)'
    );
  }
  return raw;
}
```

This validates the Route 53 hosted zone ID format (**Z** followed by alphanumeric characters). If absent (e.g., during local development or test synthesis), it returns a deterministic placeholder so **cdk synth** can run without real AWS credentials.

#### b) **parseEcsImageTag()**

```typescript
function parseEcsImageTag(raw: string | undefined): string {
  if (!raw) {
    return 'latest';
  }
  if (!/^[\w][\w.-]{0,127}$/.test(raw)) {
    throw new Error(
      'ECS_IMAGE_TAG must be a valid Docker image tag ' +
      '(max 128 chars, alphanumeric, periods, underscores, hyphens)'
    );
  }
  return raw;
}
```

Validates Docker image tag format per the OCI specification. The CI/CD pipeline sets this to the Git commit SHA — e.g., **ECS_IMAGE_TAG=abc123def456**. The deployment contract tests verify that invalid tags (like **invalid/tag**) cause synthesis to fail fast.

#### c) **parseRaftDbImageDigest()**

```typescript
function parseRaftDbImageDigest(raw: string | undefined): string {
  if (!raw) {
    return 'sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
  }
  if (!/^sha256:[a-f0-9]{64}$/.test(raw)) {
    throw new Error(
      'RAFTDB_IMAGE_DIGEST must be a SHA256 digest (sha256:<64 hex chars>)'
    );
  }
  return raw;
}
```

RaftDB images are always referenced by **immutable SHA256 digest**, never a mutable tag. This function enforces the format **sha256:<64 hex characters>**. The all-**f** placeholder digest is intentionally invalid for real ECR pulls — it only exists so **cdk synth** completes without credentials.

#### d) **parseNodeCount()**

```typescript
function parseNodeCount(raw: string | undefined): number {
  const n = Number(raw ?? '1');
  if (n !== 1 && n !== 3) {
    throw new Error('RAFTDB_NODE_COUNT must be 1 or 3');
  }
  return n;
}
```

RaftDB only supports 1-node (qualification) or 3-node (full Raft consensus) deployments. Any other value is rejected.

#### e) **parseRestoreFromS3()**

```typescript
function parseRestoreFromS3(raw: string | undefined): boolean {
  if (!raw) return false;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  throw new Error('RAFTDB_RESTORE_FROM_S3 must be "true" or "false"');
}
```

Enforces strict boolean parsing — no truthy/falsy ambiguity.

#### Validation summary

| Function | Accepts | Rejects | Placeholder for synth |
|---|---|---|---|
| **parseHostedZoneId** | **Z[A-Z0-9]+** | Missing, wrong prefix | **ZPLACEHOLDERPLACEHOLDER** |
| **parseEcsImageTag** | **[\w][\w.-]{0,127}** | Slashes, 129+ chars | **latest** |
| **parseRaftDbImageDigest** | **sha256:[a-f0-9]{64}** | Wrong length, non-hex | **sha256:ffff...ffff** |
| **parseNodeCount** | **1**, **3** | **2**, **0**, non-numeric | **1** |
| **parseRestoreFromS3** | **"true"**, **"false"** | **"yes"**, **""**, missing | **false** |

---

#### 3. AwsplaceStack — The Main Orchestrator

The **AwsplaceStack** class extends the CDK **Stack** class and wires together all infrastructure modules in a specific dependency order.

#### Constructor props

| Property | Type | Source | Example |
|---|---|---|---|
| **domainName** | **string** | **DOMAIN_NAME** env var | **place.namanhishere.com** |
| **hostedZoneId** | **string** | **HOSTED_ZONE_ID** env var (parsed) | **Z1234567890ABC** |
| **ecsImageTag** | **string** | **ECS_IMAGE_TAG** env var (parsed) | **abc123def456** (commit SHA) |
| **raftDbImageDigest** | **string** | **RAFTDB_IMAGE_DIGEST** env var (parsed) | **sha256:abcd...1234** |

#### Resource creation order

The constructor calls modules in this exact sequence:

```
 1. createVpc(this)                        → VpcOutput
 2. createDatabase(this)                   → DatabaseOutput
 3. createEcr(this)                        → EcrOutput
 4. createStorage(this, ...)               → StorageOutput
 5. createIamRoles(this, ...)              → IamOutput
 6. createRaftDbApplicationStorage(...)    → RaftDbAppStorage
 7. createRoute53AndCertificates(...)       → Route53AndCertOutput
 8. createLambda(this, ...)                → LambdaOutput
 9. createApiGateway(this, ...)            → ApiGatewayOutput
10. createAmplify(this, ...)               → AmplifyOutput
11. createEcs(this, ...)                   → EcsOutput
```

**Why this order matters:**

- **VPC first** — every network-attached resource needs subnet and AZ information.
- **Database and storage before IAM** — IAM policies need table ARNs and bucket ARNs to scope permissions.
- **IAM before Lambda and ECS** — both need their execution/task roles to exist at creation time.
- **Route 53 before API Gateway, Amplify, and ECS** — the wildcard ACM certificate must exist before any TLS-enabled resource references it.
- **ECS last** — it references VPC, IAM, ECR, database, storage, secrets, EFS, and Route 53. Creating it last ensures all dependencies are available.

![Stack Wiring Diagram](/images/5-Workshop/5.3-CDK-Project-Structure/stack-wiring.png)

#### CloudFormation Outputs

The stack emits **21 CloudFormation outputs** so CI/CD pipelines and operational scripts can reference infrastructure values without hardcoding:

| Output | Value | Consumers |
|---|---|---|
| **VpcId** | VPC ID | Operational scripts, dashboard |
| **EcsRepositoryUri** | ECR repository URI | **scripts/push-ecs-image.sh** |
| **EcsRepositoryName** | ECR repository name | Cross-stack import (staging stack), CI/CD |
| **EcsClusterName** | ECS cluster name | **aws ecs wait services-stable** |
| **EcsServiceName** | ECS service name | **aws ecs wait services-stable** |
| **EcsTaskExecutionRoleArn** | ECS execution role ARN | Operational reference |
| **EcsTaskRoleArn** | ECS task role ARN | Operational reference |
| **LambdaExecutionRoleArn** | Lambda execution role ARN | Operational reference |
| **ApiFunctionArn** | Lambda function ARN | CI/CD verification |
| **AppSecretArn** | Secrets Manager secret ARN | Rotation scripts |
| **ConfigTableName** | Config DynamoDB table name | Admin tools |
| **BansTableName** | Bans DynamoDB table name | Admin tools |
| **MilestonesTableName** | Milestones DynamoDB table name | Scheduler verification |
| **HistoryTableName** | History DynamoDB table name | Data export scripts |
| **CanvasBucketName** | Canvas S3 bucket name | Export scripts |
| **ExportsBucketName** | Exports S3 bucket name | Admin dashboard |
| **RaftDbFileSystemId** | RaftDB EFS filesystem ID | Recovery procedures |
| **RaftDbSnapshotBucketName** | RaftDB snapshot S3 bucket | Snapshot management |
| **AmplifyAppId** | Amplify application ID | **scripts/deploy-frontend.sh** |
| **AmplifyDefaultDomain** | Amplify default domain | Verification |
| **AmplifyBranchName** | Amplify production branch name | Verification |

#### Cross-stack reference

The ECR repository name is exported so the staging stack can import it via **Fn.importValue()**:

```typescript
// In AwsplaceStack:
new CfnOutput(this, 'EcsRepositoryName', {
  value: ecrRepo.repositoryName,
  exportName: 'AwsplaceEcsRepositoryName',
});

// In RaftDbStagingStack:
const repository = ecr.Repository.fromRepositoryName(
  this, 'SharedEcrRepository',
  Fn.importValue('AwsplaceEcsRepositoryName')
);
```

This is the mechanism that allows two separate CloudFormation stacks to share a single ECR repository — the staging stack pulls the same RaftDB images that the production stack uses.

---

#### 4. RaftDbStagingStack — Conditional Second Stack

When **ENABLE_RAFTDB=true**, a second CloudFormation stack is created for RaftDB qualification and recovery drills. This stack is **never used in production** — the production RaftDB runs as a sidecar in the main ECS task.

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

The **addDependency** call ensures the main stack is deployed before the staging stack — the staging stack cannot resolve **Fn.importValue('AwsplaceEcsRepositoryName')** until the main stack exists.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Open bin/ entry point file in VS Code and capture the full file showing the App creation, validation calls, and conditional staging stack logic.
Save as: static/images/5.4/entry-point-code.png

Screenshot suggestion 2: Run npx cdk synth and capture the cdk.out/ directory showing both AwsplaceStack.template.json and RaftDbStagingStack.template.json (when ENABLE_RAFTDB=true).
Save as: static/images/5.4/cdk-out-templates.png
-->
