---
title: "Week 4 Worklog"
date: 2026-07-06
weight: 4
chapter: false
pre: " <b> 1.4. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 4 Objectives:

* Describe the whole deployment as one CDK stack, so nothing about it depends on a console click I would later forget.
* Choose a network and an IAM shape I can defend: no private subnets I do not need, no policy action I cannot name.
* Get the three public hostnames answering on TLS, with the load balancer configured for connections that stay open for hours.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Write cdk/lib/vpc.ts: maxAzs 2, one public subnet group at cidrMask 24, and natGateways 0 <br> - **Accept the consequences of removing NAT rather than hiding them:** <br>&emsp; + Fargate tasks sit in public subnets and need assignPublicIp true to pull an image <br>&emsp; + isolation therefore comes from security groups, not from a routing boundary <br>&emsp; + two NAT gateways, the CDK default at maxAzs 2, would have been the largest recurring line in the bill for a single-task service <br> - Validate stack inputs in cdk/bin/app.ts so a wrong value fails at synth instead of mid-deploy | 06/07/2026 | 06/07/2026 | <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html> <br> <https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_ec2-readme.html> |
| 3   | - Define three roles in cdk/lib/iam.ts: ECS task execution, ECS task, and Lambda execution <br> - Enumerate every action explicitly instead of writing a service wildcard <br> - Scope resources to the exact bucket and object ARNs rather than to the account <br> - Keep resources star only where the API has no resource to name, which is the ECR authorization token call and the two CloudWatch Logs writes, and write down that it is deliberate | 07/07/2026 | 07/07/2026 | <https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html> <br> <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html> |
| 4   | - Build the ALB in cdk/lib/ecs.ts: internet-facing, in the public subnets, HTTPS on 443 with the wildcard certificate <br> - Add an HTTP listener on 80 that does nothing but a permanent redirect to 443 <br> - Point the target group at container port 8980 with health check /health, 30 second interval, 5 second timeout, healthy threshold 2 <br> - **Tune it for long-lived WebSocket connections:** <br>&emsp; + set idle_timeout.timeout_seconds to 3600 on the load balancer, not on the target group <br>&emsp; + set deregistration_delay.timeout_seconds to 30 on the target group | 08/07/2026 | 08/07/2026 | <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html> <br> <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html> |
| 5   | - Import the hosted zone by id in cdk/lib/route53.ts with fromHostedZoneAttributes, so synth needs no AWS credentials <br> - Request one wildcard ACM certificate for the domain and validate it by DNS against that zone <br> - Leave route53.ts free of any record: the api name is created next to the API Gateway domain, the ws name next to the load balancer, and the apex is left to Amplify <br> - Confirm the wildcard certificate is consumed by both API Gateway and the ALB | 09/07/2026 | 09/07/2026 | <https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html> <br> <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html> |
| 6   | - Create the Amplify app in cdk/lib/amplify.ts with a production branch and no source code provider, because CI uploads a zip asset rather than Amplify pulling a repository <br> - Add the SPA rewrite rules and associate the apex domain with mapRoot, leaving enableAutoSubdomain false <br> - Let Amplify manage its own certificate and its own DNS records, and record why duplicating them in CDK breaks the deploy <br> - Wire npm test in cdk/package.json to run tsc, then cdk synth, then the seven Jest contract test files against the synthesized template | 10/07/2026 | 10/07/2026 | <https://docs.aws.amazon.com/amplify/latest/userguide/redirects.html> <br> <https://docs.aws.amazon.com/amplify/latest/userguide/custom-domains.html> |

The network is 22 lines and every one of them is a decision:

```typescript
// awsplace/cdk/lib/vpc.ts
export function createVpc(scope: Construct): VpcOutput {
  const vpc = new ec2.Vpc(scope, 'AwsplaceVpc', {
    maxAzs: 2,
    natGateways: 0,
    subnetConfiguration: [
      {
        name: 'Public',
        subnetType: ec2.SubnetType.PUBLIC,
        cidrMask: 24,
      },
    ],
  });

  return { vpc };
}
```

IAM is the opposite of terse. Naming four S3 actions and four ARNs is longer than a wildcard and is the only version I can review:

```typescript
// awsplace/cdk/lib/iam.ts
ecsTaskRole.addToPolicy(
  new iam.PolicyStatement({
    actions: [
      's3:GetObject',
      's3:PutObject',
      's3:DeleteObject',
      's3:ListBucket',
    ],
    resources: [
      storage.canvasBucket.bucketArn,
      `${storage.canvasBucket.bucketArn}/*`,
      storage.exportsBucket.bucketArn,
      `${storage.exportsBucket.bucketArn}/*`,
    ],
  })
);
```

The idle timeout is the one setting I got wrong first, and the fix is recorded in the code:

```typescript
// awsplace/cdk/lib/ecs.ts
targetGroup.setAttribute('deregistration_delay.timeout_seconds', '30');
// chage from the target group to the load balancer to set the idle timeout
alb.setAttribute('idle_timeout.timeout_seconds', '3600');
```

### Week 4 Achievements:

* The whole deployment is one CloudFormation stack synthesized from TypeScript, split into per-concern modules that `cdk/lib/stack.ts` wires together. Nothing in the running system was created by hand, which means the answer to "why is this configured that way" is always a file rather than a memory.

* The VPC is deliberately minimal: `maxAzs: 2`, a single public subnet group, and `natGateways: 0`. That last line is the largest cost decision in the stack, because at `maxAzs: 2` the CDK default is one NAT gateway per availability zone, billed per hour whether or not anything egresses. Removing them is not free of consequence and I wrote the consequence down instead of glossing it: the Fargate task runs in a public subnet with `assignPublicIp: true` so it can pull its image, so the isolation that a private subnet would have given me now comes entirely from security groups. The ALB security group accepts 80 and 443 from anywhere; the task security group accepts 8980 from the ALB security group only, and nothing else. For a single-task service that is a boundary I can inspect in one place.

* Every policy in `cdk/lib/iam.ts` lists its actions one per line, and the three roles are separated by what they actually do: the task execution role pulls images and writes logs, the task role reaches the application's own storage, and the Lambda execution role gets the basic execution managed policy plus a single `s3:PutObject` on the exports prefix. Resource ARNs are named, not inherited from the account. `resources: ['*']` survives in exactly two statements, both on the execution role, and both because the API in question has no resource to scope: `ecr:GetAuthorizationToken` and the pair of CloudWatch Logs writes. Being able to state that in one sentence is the point of writing it out longhand.

* One correction worth recording: `cdk/README.md` lists `secretsmanager:GetSecretValue` under the ECS execution role, but no such statement exists in `iam.ts`. The grant is issued elsewhere, as `lambda.appSecret.grantRead(ecsTaskExecutionRole)` in `cdk/lib/stack.ts`. The secret itself is created in `cdk/lib/lambda.ts`, and the only runtime reader of it is the ECS `App` container; the Lambda duplicates the same values as plaintext environment variables and never calls Secrets Manager at all. So the documentation was right about the effect and wrong about the location, and the code is what I trust.

* TLS and DNS are split across three files on purpose, and `route53.ts` is the smallest of them: it imports the hosted zone with `fromHostedZoneAttributes` and requests one wildcard `acm.Certificate` validated by DNS. It creates no records at all. The `api` name is an alias created next to the API Gateway custom domain in `apigw.ts`, the `ws` name is an alias to the load balancer created in `ecs.ts`, and the apex is owned entirely by Amplify. Importing the zone rather than looking it up matters more than it looks: `fromHostedZoneAttributes` resolves at synth time, so `cdk synth` runs without AWS credentials, which is what lets the contract tests run in CI on a job that holds no role.

* The load balancer is configured for connections that are supposed to last. `idle_timeout.timeout_seconds` is 3600 on the load balancer itself, because a WebSocket carrying canvas updates can easily sit quiet for longer than the default 60 seconds and the ALB would otherwise close it under the client. I first set that attribute on the target group, where it does nothing, and the comment recording the move is still in `ecs.ts` as a reminder that an attribute accepted without error is not an attribute that took effect. `deregistration_delay.timeout_seconds` is 30 on the target group, so a replaced task drains rather than dropping open sockets. HTTP on 80 exists only to issue a permanent redirect to 443.

* Amplify serves the frontend with no repository connection. There is no `sourceCodeProvider` on the app and no `environmentVariables` on either the app or the branch: CI builds the frontend, zips `dist/`, and uploads it as an asset, and the API and WebSocket endpoints are baked in at build time rather than injected at runtime. The apex domain is associated with `addDomain` plus `mapRoot`, `enableAutoSubdomain` stays false, and Amplify keeps its own certificate. The comment in `amplify.ts` explains why I did not also declare those DNS records in CDK: Amplify can create them first, and the stack then fails with a record-set-already-exists error.

* `npm test` in the `cdk` package is a three-stage pipeline: `tsc`, then `cdk synth --no-strict`, then Jest over seven test files named explicitly with `--runTestsByPath`. They assert against the synthesized `AwsplaceStack` template on disk rather than mocking AWS, so they catch drift between intent and template. Two things about them are worth stating precisely. The "seven contract tests" everyone refers to are seven *files*, not seven cases; the files hold considerably more cases than that between them. And their coverage is uneven: the Amplify tests do assert that the stack emits no CloudFront distribution and no Amplify DNS records, and the deployment-contract tests re-run synth under mutated environment variables to prove that a bad image tag fails before deployment, but nothing in the suite asserts `natGateways: 0`, the 3600 second idle timeout, the IAM statements, or the wildcard certificate. Those four facts rest on review, not on a test, and that gap is the honest state of the suite at the end of this week.
