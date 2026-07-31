---
title: "Required AWS Resources"
date: 2026-07-27
weight: 4
chapter: false
pre: " <b> 5.2.4 </b> "
---

## CDK bootstrap

The CDK CLI needs a bootstrap stack in `ap-southeast-1` to store assets and grant deployment permissions. Bootstrap the region once before the first deploy:

```bash
npx cdk bootstrap aws://ACCOUNT_ID/ap-southeast-1
```

This creates a CloudFormation stack named `CDKToolkit` and an S3 bucket for staging assets. If you have already bootstrapped this account and region for another project, you can skip this step.

## The two S3 buckets you must create

The CDK stack creates most resources automatically, but two S3 buckets must exist before the first deploy. The stack imports them by name in `awsplace/cdk/lib/storage.ts`:

```typescript
const canvasBucket = s3.Bucket.fromBucketName(
  scope,
  'ImportedCanvasBucket',
  `awsplace-canvas-${account}`
);
```

An imported bucket is a reference, not a resource. CloudFormation will not create it, and the stack does not validate that it exists, so a missing bucket surfaces as a runtime access error from the running container rather than a clear synthesis-time error.

Create both buckets in `ap-southeast-1` before the first `cdk deploy`:

| Bucket | Purpose |
|---|---|
| `awsplace-canvas-ACCOUNT_ID` | Binary canvas snapshots written by the Go server |
| `awsplace-exports-ACCOUNT_ID` | PNG exports and timelapse artifacts |

```bash
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws s3api create-bucket \
  --bucket "awsplace-canvas-${ACCOUNT_ID}" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api create-bucket \
  --bucket "awsplace-exports-${ACCOUNT_ID}" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

Verify they exist:

```bash
aws s3api head-bucket --bucket "awsplace-canvas-${ACCOUNT_ID}" --region ap-southeast-1
aws s3api head-bucket --bucket "awsplace-exports-${ACCOUNT_ID}" --region ap-southeast-1
```

A silent exit 0 means the bucket is there. `404` means it still needs to be created. `403` means the name is taken by another account, which should not happen because the name embeds your account number.

## Resources created by the CDK stack

The CDK stack `AwsplaceStack` creates the following resources in dependency order:

| Resource | CDK module | Purpose |
|---|---|---|
| VPC with two public subnets | `cdk/lib/vpc.ts` | Network for ECS and EFS; no NAT gateway |
| DynamoDB tables `Config`, `Bans`, `Milestones`, `History` | `cdk/lib/database.ts` | Legacy/migration data; on-demand billing |
| ECR repository `awsplace-ecs` | `cdk/lib/ecr.ts` | Stores the Go server and RaftDB images; keeps last 10 images |
| Imported S3 buckets `awsplace-canvas-*`, `awsplace-exports-*` | `cdk/lib/storage.ts` | Canvas snapshots and PNG exports |
| IAM roles for ECS execution, ECS task, and Lambda | `cdk/lib/iam.ts` | Least-privilege runtime roles |
| EFS and S3 snapshot storage for RaftDB | `cdk/lib/raftdb-application.ts` | Persistent storage for the RaftDB sidecar |
| Wildcard ACM certificate for `*.place.namanhishere.com` | `cdk/lib/route53.ts` | TLS for the ALB and API Gateway |
| Secrets Manager secret `awsplace/app-secrets` | `cdk/lib/lambda.ts` | Holds Discord and session secrets |
| Lambda function for Discord OAuth and admin proxy | `cdk/lib/lambda.ts` | Node.js 24 runtime |
| API Gateway HTTP API v2 with custom domain `api.place.namanhishere.com` | `cdk/lib/apigw.ts` | Routes `/auth/*` and `/api/*` to Lambda |
| ECS Fargate service and ALB | `cdk/lib/ecs.ts` | Runs the Go server and RaftDB sidecar |
| Amplify Hosting app with `production` branch | `cdk/lib/amplify.ts` | Serves the static frontend |
| Route 53 records and CloudWatch log groups | `cdk/lib/route53.ts`, stack outputs | DNS and observability |

The first deployment typically takes 15–20 minutes because CloudFormation creates all these resources from scratch.

## ECR repository note

The ECR repository `awsplace-ecs` is created by the CDK stack with `RemovalPolicy.RETAIN`. This means it survives `cdk destroy` and can be re-imported on the next deployment. The repository uses `TagMutability.MUTABLE_WITH_EXCLUSION` but excludes tags matching `raftdb-*` from mutation, so RaftDB images are immutable once pushed.
