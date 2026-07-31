---
title: "IAM Permissions"
date: 2026-07-27
weight: 3
chapter: false
pre: " <b> 5.2.3 </b> "
---

The repository supports two deployment paths: local CDK commands from your shell, and GitLab CI through OIDC. The GitLab CI path is the production path. The local path is useful for development, debugging, and for the initial `cdk bootstrap` step.

## Local deploy principal

If you run `npx cdk deploy` locally, the principal needs create, update, and delete permissions on the services listed below. The CDK creates resources across seventeen services. Grant the service prefixes rather than using `"Action": "*"` across all of AWS.

| Service prefix | Needed for |
|---|---|
| `cloudformation` | Creating and updating `AwsplaceStack` |
| `sts` | Assuming the CDK bootstrap deploy roles |
| `ssm` | Reading the CDK bootstrap version parameter |
| `iam` | Creating the three roles in `cdk/lib/iam.ts` and passing them to ECS and Lambda |
| `ec2` | VPC, subnets, route tables, security groups, task ENIs |
| `ecr` | The `awsplace-ecs` repository, its lifecycle policy, and image pushes |
| `ecs` | Cluster, task definition, service |
| `elasticloadbalancing` | ALB, target group, both listeners |
| `elasticfilesystem` | File system, mount targets, access point |
| `s3` | Snapshot bucket plus the two imported buckets from section 5.2.4 |
| `lambda` | The auth function and its configuration |
| `apigateway` | The HTTP API and its `$default` route |
| `amplify` | App, `production` branch, custom domain association |
| `route53` | Reading the hosted zone and writing validation and alias records |
| `acm` | Requesting and validating the wildcard certificate |
| `secretsmanager` | Creating and reading `awsplace/app-secrets` |
| `logs` | The ECS log group and both container streams |

A practical deploy policy for the local principal is shown below. It is broad enough for the first deploy and for iterating on the stack. If your organization requires tighter permissions, scope the S3, DynamoDB, and IAM resources to the specific names used by the stack.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "sts:AssumeRole",
        "ssm:GetParameter",
        "iam:*",
        "ec2:*",
        "ecr:*",
        "ecs:*",
        "elasticloadbalancing:*",
        "elasticfilesystem:*",
        "s3:*",
        "lambda:*",
        "apigateway:*",
        "amplify:*",
        "route53:*",
        "acm:*",
        "secretsmanager:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

Run `npx cdk diff` before the first deploy. If it reports a resource type outside this list, grant that service too. Widening to a full `"Action": "*"` is the wrong repair.

## GitLab CI deploy role (OIDC)

The production pipeline authenticates through an IAM OIDC identity provider and assumes a dedicated deploy role. The role is named `GitLabCDKDeployRole` and is shown in the screenshots in section 5.2.7.

The trust policy below restricts the role to the `main` branch of the `namanhishere/awsplace` project on the GitLab instance `git.namanhishere.com`. Replace `ACCOUNT_ID` with your AWS account number.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/git.namanhishere.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "git.namanhishere.com:aud": "https://git.namanhishere.com"
        },
        "StringLike": {
          "git.namanhishere.com:sub": "project_path:namanhishere/awsplace:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

The `sub` claim in a GitLab OIDC token looks like:

```
project_path:namanhishere/awsplace:ref_type:branch:ref:main
```

If you want to deploy from other branches, widen the `StringLike` pattern. For example, to allow any branch:

```
project_path:namanhishere/awsplace:ref_type:branch:ref:*
```

For production, keep the restriction to `main`.

Attach the same service-level permissions listed in the local deploy table to the `GitLabCDKDeployRole`. The pipeline does not need long-term access keys. It receives temporary credentials through `sts:AssumeRoleWithWebIdentity` with a one-hour expiration.

## IAM details to know before debugging

Two permission details are worth knowing before they surprise you later:

- The ECS execution role gets `secretsmanager:GetSecretValue` scoped to the one secret ARN. The app container reads the secret at task start.
- The Lambda receives the same secret values as plain environment variables injected at synthesis time. Rotating the secret requires a Lambda redeploy; ECS only needs a task restart.
