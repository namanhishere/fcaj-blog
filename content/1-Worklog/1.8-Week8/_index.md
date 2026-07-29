---
title: "Week 8 Worklog"
date: 2026-08-03
weight: 8
chapter: false
pre: " <b> 1.8. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 8 Objectives:

* Cut production over to `DATA_MODE=raftdb-only`, so the application has exactly one datastore and no fallback path.
* Make the deployment strategy honest about the constraint underneath it: one RaftDB writer owns the EFS write-ahead log, so two tasks must never run at once.
* Qualify the image with a real round-trip probe rather than a health check, and record what the observability story actually is today instead of what the dashboard implies.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Re-read the mode contract before changing anything: DATA_MODE is the runtime selector for storage behaviour, and changing it is a task-definition deployment, not an image rebuild <br> - **Confirm where raftdb-only sits in the sequence:** <br>&emsp; + legacy, then dual-write-read-legacy, then dual-write-read-raftdb, then raftdb-only <br>&emsp; + rollback is only permitted while the legacy store is still complete and authoritative <br> - Note that raftdb-only forces both interfaces to RaftDB and ignores stale legacy selector values <br> - Accept the consequence: once the rollback window closes, RaftDB is the only store | 03/08/2026 | 03/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html> |
| 3   | - Set DATA_MODE, BACKEND and STORAGE to the raftdb values on the App container and point RAFTDB_ADDR at 127.0.0.1:9100 <br> - Make RaftDB a required sidecar in the same task rather than a separate service, so the loopback address is the whole network path <br> - Add the container dependency so ECS starts App only after RaftDb reports HEALTHY <br> - Derive ALLOWED_ORIGINS from the deployed domain so a clean deployment cannot silently fall back to same-origin only | 04/08/2026 | 04/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking-awsvpc.html> <br> <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html> |
| 4   | - Pin the deployment percentages to minHealthyPercent 0 and maxHealthyPercent 100, and write the reason into the source next to them <br> - Set stopTimeout to 120 seconds on the RaftDb container so the WAL has time to flush before the task is killed <br> - **Add the deployment circuit breaker with rollback as a raw DeploymentConfiguration.DeploymentCircuitBreaker property override:** <br>&emsp; + the L2 property also emits DeploymentController, which would replace the running service <br>&emsp; + acknowledge the resulting CDK warning explicitly rather than silencing it <br> - Keep desiredCount at 1 and add no autoscaling anywhere | 05/08/2026 | 05/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html> <br> <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html> |
| 5   | - Read the raftdb-qualify client and write down what it does and does not prove: two subcommands write-read and read, required flags --key and --value-base64, a 30 second overall timeout <br> - **Fix the exit-code contract in my own notes:** <br>&emsp; + 0 qualification passed and JSON evidence written <br>&emsp; + 2 usage or validation error <br>&emsp; + 1 runtime failure, including a value mismatch <br> - Run the qualification contract test, which writes, restarts the server, then reads the value back <br> - Record that the container health check is a shallow probe: ready file, writable data directory, TCP connect, no protocol handshake | 06/08/2026 | 06/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html> |
| 6   | - Deploy with the RaftDB image referenced by digest and watch the rollout reach PRIMARY with one running task <br> - Confirm the task shape: two containers, RaftDb on 9100 and App on 8980, EFS mounted at /data/raftdb through the access point /raftdb/production/member-1 <br> - Read the CloudWatch dashboard definition and record the honest state: the RaftDb custom namespace is provisioned but dormant, because no publisher exists in the tree yet <br> - Write down that production has no CloudWatch alarms today and that every RaftDB alarm lives in the staging stack | 07/08/2026 | 07/08/2026 | <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html> <br> <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html> |

The comment that explains the deployment strategy is in the CDK next to the values it justifies, which is where it belongs:

```typescript
// awsplace/cdk/lib/ecs.ts
desiredCount: 1,
// A single raftdb writer owns the EFS WAL. Stop it before replacement;
// overlapping tasks would open the same durable files concurrently.
minHealthyPercent: 0,
maxHealthyPercent: 100,
```

The circuit breaker is applied to the existing service rather than through the higher-level property, for a reason that is also recorded in the source:

```typescript
// awsplace/cdk/lib/ecs.ts
const cfnService = service.node.defaultChild as ecs.CfnService;
cfnService.addPropertyOverride('DeploymentConfiguration.DeploymentCircuitBreaker', {
  Enable: true,
  Rollback: true,
});
```

### Week 8 Achievements:

* Production runs a single datastore. The App container carries `DATA_MODE=raftdb-only`, `BACKEND=raftdb`, `STORAGE=raftdb` and `RAFTDB_ADDR=127.0.0.1:9100`, and RaftDB is a required sidecar in the same ECS task rather than a service of its own. `awsplace/docs/raftdb/application-modes.md` is explicit that this is the final state after the rollback window closes, and that `raftdb-only` forces both interfaces to RaftDB and ignores stale legacy selector values. The service runs one task with those two containers, `RaftDb` on 9100 and `App` on 8980, with the RaftDB image referenced by digest rather than by tag.

* Ordering is enforced by the platform, not by a retry loop. `appContainer.addContainerDependencies` with `ContainerDependencyCondition.HEALTHY` means ECS does not start the application until the sidecar's health check passes, and that health check runs every 5 seconds with a 15 second start period and up to 10 retries. Since the application's only datastore is reached over loopback, there is no case where the app is up and the store is unreachable across a network.

* The deployment strategy is a deliberate availability cost, written down as one. `minHealthyPercent: 0` and `maxHealthyPercent: 100` make every deploy stop-then-start rather than rolling, because one RaftDB writer owns the EFS write-ahead log and two overlapping tasks would open the same durable files. `stopTimeout` is 120 seconds so the outgoing container can flush before it is killed. The canvas is therefore offline for the length of every deployment. I preferred a short, predictable outage to the possibility of two writers on one WAL.

* The rollback guard is a raw CloudFormation property override, and that detail matters if anyone reads the CDK later. Setting the L2 `circuitBreaker` property would also emit `DeploymentController`, which CloudFormation treats as a replacement of the running service; overriding `DeploymentConfiguration.DeploymentCircuitBreaker` with `Enable` and `Rollback` set updates the live service in place instead. The CDK warning about not using the L2 property is acknowledged explicitly in the code rather than suppressed, and the synthesized template is asserted in `awsplace/cdk/deployment-contract.test.cjs`. `desiredCount` stays 1 and there is no autoscaling construct anywhere in the CDK, so the capacity story really is one task.

* `raftdb-qualify` proves something the health check cannot. The health check confirms the readiness marker is non-empty, the data directory is a writable directory, and a TCP connection to `127.0.0.1` on the client port succeeds; it performs no protocol handshake and asserts nothing about leadership or quorum. `raftdb-qualify` writes a prefix-scoped key with `write-read`, and the qualification contract test then stops the server, restarts it, and runs `read` to require the value back byte for byte. That is a durability check across a restart rather than a liveness check. It is a staging and drill tool, not a production component, and its CDK task definition ships with a deliberately invalid command so the mode has to be supplied at run time.

* Observability is where I have to be careful, because the dashboard looks more complete than the system is. `awsplace/cdk/lib/dashboard.ts` defines nine metric names under the custom namespace `RaftDb` and lays them out over four widgets, and its own header comment says the panels "are dormant until the Raft runtime actually publishes the values". No publisher exists: the `RAFTDB_METRICS_*` variables are listed as reserved but inactive in the runtime contract, and there is no metric-publishing call in the RaftDB or Go sources. So the namespace is provisioned but dormant, and I have no measured value from it to report. Container logs are real, one stream prefix per container, `raftdb` and `awsplace`.

* Two gaps are now written down rather than assumed away. Production has no CloudWatch alarms at all: every RaftDB alarm, including snapshot age over 900 seconds and any WAL error, lives in the staging stack that only exists when `ENABLE_RAFTDB` is set, and two of those alarms watch the same dormant namespace with `treatMissingData: NOT_BREACHING`, so they would sit in insufficient-data rather than fire. Production's only automatic safety net is the deployment circuit breaker. Separately, `application-modes.md` documents startup-time fail-closed behaviour and the ECS start ordering, but says nothing about what the application does if the sidecar becomes unavailable mid-flight while in `raftdb-only`; that behaviour is undocumented, and I am not going to describe it as if it were designed.
