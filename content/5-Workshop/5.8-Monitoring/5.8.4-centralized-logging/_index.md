---
title: "Centralized Logging"
date: 2024-01-01
weight: 4
chapter: false
pre: " <b> 5.8.4. </b> "
---

Every container in the awsplace project streams its logs to CloudWatch Logs using the **awslogs** log driver. No logs stay on the container filesystem — they are pushed to CloudWatch where they survive task replacements, can be queried with CloudWatch Logs Insights, and are retained by log-group policies. The logging strategy uses dedicated stream prefixes, private VPC endpoints for isolated tasks, and scoped IAM permissions.

#### Log stream strategy

| Container | Log Group Stream Prefix | Source File | Purpose |
|---|---|---|---|
| RaftDB (production sidecar) | **raftdb** | Infrastructure | Raft consensus events, snapshot publication, health transitions |
| Application (Go/ECS) | **awsplace** | Infrastructure | HTTP request logs, WebSocket events, DynamoDB operations, RaftDB client operations |
| RaftDB (staging members) | **raftdb** | Infrastructure | Per-member consensus events, peer communication, WAL operations |
| RaftDB qualification tasks | **raftdb-qualification** | Infrastructure | Qualification test output, client-side metrics, failure diagnostics |

Each stream prefix creates a separate CloudWatch log stream within the log group. The **awslogs** driver is configured inline in the container definition:

```typescript
// Production sidecar
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'raftdb' }),

// Application container
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'awsplace' }),

// Staging members
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'raftdb' }),

// Qualification tasks
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'raftdb-qualification' }),
```

---

#### 1. IAM Permissions for Logging

Function: **createIamRoles**

The ECS task execution role carries the minimum permissions needed for the awslogs driver to create streams and publish events:

```typescript
ecsTaskExecutionRole.addToPolicy(
  new iam.PolicyStatement({
    actions: [
      'logs:CreateLogStream',
      'logs:PutLogEvents',
    ],
    resources: ['*'],
  })
);
```

The **logs:CreateLogGroup** permission is intentionally **not** granted — log groups are created by CDK at deployment time, not by the container at runtime. This follows the principle of least privilege: a compromised container cannot create new log groups to hide its activity.

The Lambda execution role uses the AWS-managed policy **AWSLambdaBasicExecutionRole**, which includes CloudWatch Logs write permissions for Lambda function logs.

---

#### 2. Private VPC Endpoint for Isolated Tasks

Function: **createRaftDbCluster**

RaftDB staging members run in private isolated subnets with no NAT gateway and no public IP (when deployed as a 3-node cluster). For these tasks to push logs to CloudWatch, the CDK provisions a private **CloudWatch Logs VPC interface endpoint**:

```typescript
vpc.addInterfaceEndpoint('RaftDbLogsEndpoint', {
  ...interfaceEndpointOptions,
  service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
});
```

This endpoint is part of a set of three private interface endpoints (ECR API, ECR Docker, CloudWatch Logs) and one S3 gateway endpoint. The endpoint security group accepts TCP 443 only from the RaftDB task group — no other traffic can reach the CloudWatch Logs service through this path.

The full set of VPC endpoints for isolated staging tasks is validated by the test **three-member raftdb reaches every AWS service it needs through private endpoints** in **raftdb.test.cjs**.

---

#### 3. Log Retention and Querying

CloudWatch Logs groups are created implicitly by ECS when the first log event is published (or explicitly by CDK if retention policies are set). Once logs are in CloudWatch:

- **CloudWatch Logs Insights** can query across log groups using the stream prefix to filter by container type. For example, to find all RaftDB health-check failures across the staging cluster:

  ```
  fields @timestamp, @logStream, @message
  | filter @logStream like /raftdb/
  | filter @message like /health/
  | sort @timestamp desc
  | limit 100
  ```

- **Metric filters** can be applied to log groups to extract custom metrics from log patterns — for instance, counting the number of "quorum lost" messages per hour.
- **Subscription filters** can stream logs to Lambda, Kinesis, or OpenSearch for real-time processing and alerting beyond what CloudWatch Alarms provide.

---

#### 4. Logging in the CI/CD Pipeline

The CI/CD pipeline also produces structured logs that complement the runtime monitoring:

| Pipeline Stage | Log Output | Retention |
|---|---|---|
| Go unit tests | Test function names and failure messages in GitHub Actions logs | 90 days (default) |
| CDK test suite | Jest output with pass/fail per test file | 90 days (default) |
| RaftDB image chain of custody | Image ID, scan results, contract test output as workflow artifacts | 90 days (explicit artifact upload) |
| Trivy vulnerability scan | SARIF report with HIGH/CRITICAL finding details | 90 days (explicit artifact upload) |

The RaftDB publication evidence (image digest, contract test results, scan report) is uploaded as a workflow artifact with 90-day retention. This provides an audit trail connecting a running container to its build, test, and scan provenance.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Open CloudWatch Logs Insights in the AWS Console.
Run a query filtering by a log group for the awsplace application.
Capture the interface showing the query editor, the log stream selector, and a sample of results.
Save as: static/images/5.7/logs-insights-query.png

Screenshot suggestion 2: Open the ECS task details for a running RaftDB member.
Scroll to the "Logs" tab and capture the live log tail showing recent entries with timestamps and the awslogs driver configuration.
Save as: static/images/5.7/ecs-container-logs.png

Screenshot suggestion 3: Navigate to VPC Endpoints in the AWS Console.
Filter by the RaftDB VPC and capture the list showing the CloudWatch Logs endpoint alongside ECR and S3 endpoints.
Save as: static/images/5.7/vpc-endpoints-logging.png
-->
