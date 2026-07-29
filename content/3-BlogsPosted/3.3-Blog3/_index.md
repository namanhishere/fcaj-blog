---
title: "How Amazon EFS shortened my development loop while building a Raft datastore"
date: 2026-07-27
weight: 3
chapter: false
pre: " <b> 3.3. </b> "
includeInReport: false
---

# The situation

The production datastore of my internship project is not a managed service. It is a C++23 server called RaftDB that runs as a sidecar container inside the same ECS Fargate task as the Go application. The application talks to it over `127.0.0.1:9100` with `DATA_MODE=raftdb-only`, so every pixel on the collaborative canvas, along with the config, bans, milestones and placement history, lives in that one process (`awsplace/cdk/lib/ecs.ts:130-140`).

RaftDB keeps its state on disk. Its runtime contract is explicit about the layout: the writable data root is `/data/raftdb`, the write-ahead log goes in `/data/raftdb/wal`, local checkpoints go in `/data/raftdb/snapshots`, and the process publishes an ephemeral readiness marker at `/tmp/raftdb-ready` only after recovery finishes (`awsplace/docs/raftdb/runtime-contract.md:34-41`).

Fargate does not keep containers. Every `cdk deploy`, every new image digest, every `force-new-deployment` replaces the task with a brand new one. So I had a process whose entire value is the bytes it wrote to disk, running on a platform that throws the disk away.

# What an empty WAL cost me

Locally this was never a problem, because Docker Compose already gave me a durable disk. The `raftdb` service mounts a named volume, and a named volume survives `docker compose down`:

```yaml
services:
  raftdb:
    build:
      context: .
      dockerfile: raftdb/Dockerfile
    container_name: awsplace-raftdb
    environment:
      RAFTDB_PORT: "9100"
      RAFTDB_DATA_DIR: /data/raftdb
    volumes:
      - raftdb_data:/data/raftdb
    ports:
      - "9100:9100"

volumes:
  pg_data:
  raftdb_data:
```

That snippet is condensed from `awsplace/docker-compose.yml:7-19` and `:138-140`. Rebuild the image, restart the container, and the WAL segments and snapshot catalog under `/data/raftdb` are still there. My local canvas kept its pixels across a rebuild without me doing anything.

On Fargate, before I attached durable storage, the opposite happened. The replacement task booted with an empty `/data/raftdb`. There was no WAL tail to replay and no snapshot to restore, so every deploy handed me a blank board. Testing anything that depended on existing state meant re-seeding the canvas by hand first, and I was deploying several times an hour. The interesting part of the work, watching how the server recovered, was the exact part I could not observe, because there was never anything to recover from.

# Why EFS and not the alternatives

I looked at three other options before mounting Amazon EFS, and each failed for a specific reason.

An **EBS volume** is attached to one compute instance at a time. For a Fargate task replacement, the new task is a different task with its own lifecycle, and I would need the volume detached from the dying task and re-attached to the new one at exactly the right moment. That handoff is not something the ECS deployment gives me for free, and getting it wrong means the replacement task fails to mount at all.

**Amazon S3** is not a filesystem. RaftDB appends to its write-ahead log in place, and it replays the WAL tail on startup (`runtime-contract.md:114-116`). S3 objects are immutable: an append means rewriting the object. S3 is still in the design, but as the destination for whole checkpoints, not as the WAL device.

A **task-scoped ephemeral volume** is destroyed with the task by definition. That is the exact failure I already had.

Amazon EFS is the one option that is a POSIX filesystem, can be mounted by whichever task exists right now, and outlives all of them. The CDK for it is short:

```typescript
const fileSystem = new efs.FileSystem(scope, 'RaftDbApplicationFileSystem', {
  vpc: props.vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
  encrypted: true,
  removalPolicy: RemovalPolicy.DESTROY,
});
const accessPoint = fileSystem.addAccessPoint('ApplicationAccessPoint', {
  path: '/raftdb/production/member-1',
  createAcl: { ownerUid: '10001', ownerGid: '10001', permissions: '0750' },
  posixUser: { uid: '10001', gid: '10001' },
});

props.taskRole.addToPrincipalPolicy(new iam.PolicyStatement({
  actions: ['elasticfilesystem:ClientMount', 'elasticfilesystem:ClientWrite'],
  resources: [fileSystem.fileSystemArn],
  conditions: {
    StringEquals: { 'elasticfilesystem:AccessPointArn': accessPoint.accessPointArn },
  },
}));
```

That is `awsplace/cdk/lib/raftdb-application.ts:32-51`. The task definition then declares the volume with transit encryption and IAM authorization turned on and mounts it at the path RaftDB already expects:

```typescript
taskDefinition.addVolume({
  name: 'raftdb-data',
  efsVolumeConfiguration: {
    fileSystemId: raftDb.fileSystem.fileSystemId,
    transitEncryption: 'ENABLED',
    authorizationConfig: {
      accessPointId: raftDb.accessPoint.accessPointId,
      iam: 'ENABLED',
    },
  },
});

raftDbContainer.addMountPoints({
  sourceVolume: 'raftdb-data',
  containerPath: '/data/raftdb',
  readOnly: false,
});
```

From `awsplace/cdk/lib/ecs.ts:87-125`. Note what did not change: the container still writes to `/data/raftdb`, exactly as it does under Docker Compose. The local loop and the deployed loop now share one durability contract instead of two different designs.

<figure>
  <img src="/images/3-BlogsPosted/3.3-Blog3/efs-console.png" alt="Amazon EFS console showing the RaftDB file system with General Purpose performance, Bursting throughput, regional availability and encryption enabled" loading="lazy">
  <figcaption>The production file system after creation. General Purpose performance mode and Bursting throughput are the defaults the CDK code above produces.</figcaption>
</figure>

# The access point does the identity work

The RaftDB container runs as `user: '10001:10001'` and must start without root privileges (`ecs.ts:101`, `runtime-contract.md:43-46`). A plain NFS mount would have handed it a directory owned by root, and the first WAL write would have failed with a permission error. The usual workaround is an entrypoint that runs `chown` before dropping privileges, which needs root in the container to begin with.

The access point removes that step. `createAcl` makes EFS create `/raftdb/production/member-1` owned by uid and gid `10001` with mode `0750`, and `posixUser` forces every request through the access point to be evaluated as that same uid and gid. The container's own numeric identity matches the directory it lands in, so there is no `chown`, no root, and no init script.

The access point is also the authorization boundary. The IAM statement above grants `ClientMount` and `ClientWrite` on the file system only when `elasticfilesystem:AccessPointArn` equals this one access point, so the task role cannot reach any other directory on the same file system even if one existed. `runtime-contract.md:100-101` states the same rule from the other direction: IAM remains the authorization boundary for the EFS access point.

The same construct is what makes a future multi-voter cluster possible. `awsplace/cdk/lib/raftdb.ts:388-408` builds one access point per member at `/raftdb/${dataGeneration}/member-${nodeId}`, where `dataGeneration` is supplied by the environment, so three voters can share one file system and still be unable to touch each other's WAL. That is the documented staging target in `RaftDbStagingStack`, not what runs today. Production is one voter with `desiredCount: 1` and the single literal path `/raftdb/production/member-1`.

# The price: stop-then-start deploys

Here is the part I did not anticipate. Durable storage changed the deployment strategy, and not in a comfortable direction.

RaftDB has exactly one writer, and Raft leader fencing does not exist yet (`runtime-contract.md:78-80`). If ECS did a normal rolling deployment, the new task would mount `/raftdb/production/member-1` while the old task still had the WAL open. Two processes appending to the same log files is corruption, not a race I can retry. So the service is configured to make overlap impossible:

```typescript
const service = new ecs.FargateService(scope, 'Service', {
  cluster,
  taskDefinition,
  desiredCount: 1,
  // A single raftdb writer owns the EFS WAL. Stop it before replacement;
  // overlapping tasks would open the same durable files concurrently.
  minHealthyPercent: 0,
  maxHealthyPercent: 100,
  // ...
});
```

`minHealthyPercent: 0` is permission for ECS to take the running task count to zero. `maxHealthyPercent: 100` forbids it from ever running two. Together they turn a rolling replacement into stop-then-start (`awsplace/cdk/lib/ecs.ts:159-170`).

The cost is plain: the canvas is unreachable for the whole deployment window, on every single deploy. There is no overlap to hide behind, no second task serving traffic, and no task-count autoscaling either, since a second task would be a second writer. I chose that over the alternative, which is a corrupt WAL.

The other half of the arrangement is shutdown time. `stopTimeout: Duration.seconds(120)` gives the container the ECS maximum to handle `SIGTERM` (`ecs.ts:119`). Graceful shutdown stops accepting clients, closes connection threads, and publishes a final checkpoint, exiting 0 only if that checkpoint succeeded (`runtime-contract.md:118-123`). If the task is killed instead, acknowledged commands still recover from the synchronized WAL on EFS, which is precisely the property that made the durable mount worth its availability cost.

Startup is the mirror image. The replacement task mounts the same access point, validates the selected snapshot before binding the client port, restores it, and replays the WAL tail. Missing, corrupt or mismatched data fails startup rather than seeding an empty database (`runtime-contract.md:114-116`). The health command requires `/tmp/raftdb-ready` and writes a probe file below the data root, so a read-only or unavailable mount fails health instead of pretending to be up (`:105-112`). The App container waits for the RaftDb container to report `HEALTHY` before it starts.

<figure>
  <img src="/images/diagrams/raftdb-efs-devloop.svg" alt="Activity diagram of the RaftDB development and deploy loop: local named volume, immutable image publication, stop-then-start deployment onto the same EFS access point, snapshot restore and WAL replay, contrasted with the discarded ephemeral-volume path" loading="lazy">
  <figcaption>The whole loop. The left branch is what the EFS access point makes possible; the right branch is what a task-scoped volume would do to the canvas on every deploy.</figcaption>
</figure>

The result is the thing I actually wanted from the beginning. A deploy is now a recovery exercise I can watch, and the canvas on the other side of it is the canvas I left behind.

# What EFS did not solve

Three limits are worth stating plainly rather than glossing over.

**I did not measure it.** A write-ahead log is a latency-sensitive, small-append workload, and NFS over the network is not a local SSD. Throughput mode and per-operation latency are exactly the things that deserve a measurement here, and I have not taken one. I am not going to put a number in this post that I did not observe. The next step is the EFS metrics in CloudWatch, watched during a real canvas session rather than at idle.

<figure>
  <img src="/images/3-BlogsPosted/3.3-Blog3/efs-metrics.png" alt="Amazon CloudWatch monitoring metrics for the RaftDB EFS file system showing throughput utilization, IOPS by type, throughput by type and client connections" loading="lazy">
  <figcaption>The Monitoring tab of the file system during a RaftDB run. These are the metrics I still need to measure and interpret.</figcaption>
</figure>

**One file system is one failure domain.** Durable is not the same as redundant. If the file system or the single access-point directory under it becomes unavailable or corrupt, the one voter has nothing to fall back to locally, and the health command will fail on the unavailable mount exactly as designed.

**That is why S3 stays in the picture.** The RaftDb container is configured with `RAFTDB_SNAPSHOT_INTERVAL_SECONDS=300` and a snapshot bucket under the prefix `production/member-1`, so a checkpoint is published on that cadence and again during graceful shutdown (`ecs.ts:104-110`). The bucket is versioned, encrypted, SSL-enforced, blocks public access, and expires noncurrent versions after 35 days (`raftdb-application.ts:18-30`). Restoring from it is deliberately manual: `RAFTDB_RESTORE_FROM_S3` is `false` in production and requires an empty local snapshot catalog and WAL directory when set to `true`, because it is an explicit recovery operation and not an automatic fallback (`runtime-contract.md:73-77`).

EFS made my development loop shorter by making state survive the thing that keeps destroying it. It did not make the state safe on its own, and treating a single file system as a backup would be the wrong lesson to take from it.

## References

- [Working with Amazon EFS access points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html)
- [Amazon ECS: using Amazon EFS volumes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html)
- [Amazon EFS performance](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [Amazon ECS rolling update deployment: minimumHealthyPercent and maximumPercent](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html)
- [Docker: persist data with volumes](https://docs.docker.com/engine/storage/volumes/)
