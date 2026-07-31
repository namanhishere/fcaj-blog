---
title: "Resource Removal Policy Design"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.9.1. </b> "
---

Every stateful resource in the awsplace CDK codebase carries an explicit **RemovalPolicy** — either **RETAIN** (survive stack deletion) or **DESTROY** (be deleted with the stack). No resource is left to the CloudFormation default. These choices are enforced by the Jest contract tests in **raftdb.test.cjs** and **deployment-contract.test.cjs**, which assert that critical production resources — especially the ECR repository — carry the correct policy.

#### Removal policy inventory

| Resource | Stack | Policy | Source File | Rationale |
|---|---|---|---|---|
| ECR Repository (awsplace-ecs) | AwsplaceStack | **RETAIN** | Infrastructure | CI publishes images before stack recreation; the registry must survive cdk destroy |
| RaftDB staging snapshot bucket | RaftDbStagingStack | **RETAIN** | Infrastructure | Staging snapshot data and qualification evidence must persist across staging teardowns |
| RaftDB staging EFS | RaftDbStagingStack | **RETAIN** | Infrastructure | Durable WAL data is intentionally retained; cleanup is a separate destructive procedure |
| RaftDB application snapshot bucket | AwsplaceStack | **DESTROY** | Infrastructure | Production sidecar snapshots are local; the bucket is for the sidecar's own use and is deleted with autoDeleteObjects |
| RaftDB application EFS | AwsplaceStack | **DESTROY** | Infrastructure | Production sidecar EFS volume is transient — data lives in DynamoDB; no need to retain |
| Secrets Manager secret | AwsplaceStack | **RETAIN** | Infrastructure | Application secrets must survive stack recreation to avoid manual secret re-entry |

---

#### 1. ECR Repository: RETAIN with Lifecycle

Function: **createEcr**

The ECR repository is the most critical retained resource. The rationale is documented in the code:

```typescript
// CI publishes before the application stack is recreated, so the registry
// must survive `cdk destroy` and be auto-imported on the next deployment.
repository.applyRemovalPolicy(RemovalPolicy.RETAIN);
```

The deployment workflow depends on this behavior:

1. CI builds and pushes the Docker image to the **awsplace-ecs** repository with an immutable tag.
2. The CDK deployment references that same repository by name via **Fn.importValue**.
3. If the stack is destroyed and recreated, the new stack re-imports the existing repository by its physical name.

The repository also has a lifecycle rule that limits retained images:

```typescript
repository.addLifecycleRule({
  maxImageCount: 10,
  rulePriority: 1,
  tagStatus: ecr.TagStatus.ANY,
});
```

This keeps the most recent 10 images (tagged and untagged) and automatically expires older ones, preventing unbounded storage growth. RaftDB images prefixed with **raftdb-*** are additionally protected by an image-tag immutability exclusion filter, meaning they cannot be overwritten but are still subject to the lifecycle count.

The Jest test **application ECR repository has a stable retained physical name** in **deployment-contract.test.cjs** validates:

```javascript
test('application ECR repository has a stable retained physical name', () => {
  const repositories = resourcesByType(defaultTemplate, 'AWS::ECR::Repository');
  expect(repositories).toHaveLength(1);
  expect(repository.Properties).toEqual(expect.objectContaining({
    RepositoryName: 'awsplace-ecs',
    ImageScanningConfiguration: { ScanOnPush: true },
    ImageTagMutability: 'MUTABLE_WITH_EXCLUSION',
  }));
  expect(repository.DeletionPolicy).toBe('Retain');
});
```

---

#### 2. RaftDB Staging Resources: RETAIN

Function: **createRaftDbCluster**

The staging snapshot bucket and EFS filesystem are both set to **RETAIN**:

```typescript
// Snapshot bucket
const snapshotBucket = new s3.Bucket(scope, 'RaftDbSnapshotBucket', {
  versioned: true,
  encryption: s3.BucketEncryption.KMS_MANAGED,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  enforceSSL: true,
  removalPolicy: RemovalPolicy.RETAIN,
  lifecycleRules: [{
    id: 'RetainCurrentSnapshotsAndPreviousPointerVersions',
    enabled: true,
    noncurrentVersionExpiration: Duration.days(35),
    abortIncompleteMultipartUploadAfter: Duration.days(1),
  }],
});

// EFS filesystem
const fileSystem = new efs.FileSystem(scope, 'RaftDbFileSystem', {
  vpc,
  vpcSubnets: isolatedSubnets,
  encrypted: true,
  removalPolicy: RemovalPolicy.RETAIN,
});
```

The staging runbook (**docs/raftdb/staging-runbook.md**) explicitly states that recreating the stack creates new resources — it does not reattach retained resources automatically. This means:

- Destroying and recreating **RaftDbStagingStack** leaves the old snapshot bucket and EFS filesystem orphaned.
- The new stack creates fresh resources with new physical IDs.
- The orphaned resources require a separate, documented cleanup procedure (covered in 5.8.3).

The Jest test **raftdb snapshots use a retained private versioned bucket with lifecycle** in **raftdb.test.cjs** validates this configuration.

---

#### 3. Application-Side RaftDB Resources: DESTROY

Function: **createRaftDbApplicationStorage**

In contrast to the staging stack, the production application's RaftDB sidecar resources use **DESTROY**:

```typescript
// Application snapshot bucket
const snapshotBucket = new s3.Bucket(scope, 'RaftDbApplicationSnapshots', {
  versioned: true,
  encryption: s3.BucketEncryption.S3_MANAGED,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  enforceSSL: true,
  removalPolicy: RemovalPolicy.DESTROY,
  autoDeleteObjects: true,
  lifecycleRules: [{
    noncurrentVersionExpiration: Duration.days(35),
    abortIncompleteMultipartUploadAfter: Duration.days(1),
  }],
});

// Application EFS
const fileSystem = new efs.FileSystem(scope, 'RaftDbApplicationFileSystem', {
  vpc: props.vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
  encrypted: true,
  removalPolicy: RemovalPolicy.DESTROY,
});
```

The key difference is **autoDeleteObjects: true** on the application snapshot bucket. This setting deploys a custom resource (a Lambda function) that empties the bucket before CloudFormation deletes it — required because CloudFormation refuses to delete a non-empty S3 bucket. The staging bucket intentionally omits this setting because staging snapshot data is considered qualification evidence that must survive stack teardown.

---

#### 4. Secrets Manager: RETAIN

Function: **createLambda**

The application secret (Discord OAuth credentials, session secret) is retained:

```typescript
appSecret.applyRemovalPolicy(RemovalPolicy.RETAIN);
```

This prevents a stack recreation from destroying and requiring manual re-entry of secrets. On stack recreation, the CDK code uses **--import-existing-resources** to adopt the retained secret back into the new stack.

---

#### Policy Decision Summary

| Question | Answer | Applies To |
|---|---|---|
| Does the resource hold data that must survive a stack recreation? | **RETAIN** | ECR, staging snapshots, staging EFS, Secrets Manager |
| Is the resource's data reconstructable from other sources? | **DESTROY** | Application EFS, application snapshot bucket |
| Could accidental deletion cause data loss with no recovery path? | **RETAIN** + no autoDeleteObjects | Staging snapshot bucket |
| Is the resource safe to delete but would block stack deletion if non-empty? | **DESTROY** + autoDeleteObjects | Application snapshot bucket |

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: In the CloudFormation console, select a resource from the AwsplaceStack (e.g., the ECR repository).
Capture the resource detail showing the DeletionPolicy: Retain field.
Save as: static/images/5.8/retain-policy-ecr.png
-->
