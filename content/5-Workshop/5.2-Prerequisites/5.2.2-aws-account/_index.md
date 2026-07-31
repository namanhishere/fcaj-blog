---
title: "AWS Account"
date: 2026-07-27
weight: 2
chapter: false
pre: " <b> 5.2.2 </b> "
---

## Choosing an account

Use an AWS account you are willing to bill. The pipeline creates billable resources: a VPC, an Application Load Balancer, Fargate tasks, DynamoDB tables on on-demand billing, S3 storage, ECR storage, API Gateway, Amplify Hosting, CloudWatch Logs, and Route 53 queries. Set up a billing alarm if you are using a personal account.

## Region lock

Every command in the pipeline targets `ap-southeast-1` explicitly. The CDK entry point `awsplace/cdk/bin/app.ts` defaults to `ap-southeast-1` when `CDK_DEFAULT_REGION` is unset, but the pipeline sets `AWS_REGION: ap-southeast-1` in every job. This prevents a stale `AWS_DEFAULT_REGION` from silently redirecting resources to another region.

## Note your account ID

Many resource names and ARNs in this workshop include the 12-digit AWS account number. Throughout these pages it is written as `ACCOUNT_ID`; substitute your own.

```bash
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "$ACCOUNT_ID"
```

## AWS CLI v2 login

The pipeline itself uses OIDC, but you still need local AWS credentials for the setup steps in this section. Install AWS CLI v2 and run `aws login` to authenticate through IAM Identity Center or AWS CLI SSO.

```bash
aws login
```

The command prints a URL and opens a browser session.

![AWS CLI login prompt](/images/5-Workshop/5.2-Prerequisite/awslogincli.png)

The browser page asks you to confirm the session.

![AWS sign-in confirmation](/images/5-Workshop/5.2-Prerequisite/awsloginui.png)

After login, confirm the region and identity:

```bash
aws sts get-caller-identity --region ap-southeast-1
```

Expected output:

```json
{
    "UserId": "AIDAEXAMPLEUSERID",
    "Account": "ACCOUNT_ID",
    "Arn": "arn:aws:iam::ACCOUNT_ID:user/your-deploy-user"
}
```


If the command prints `Unable to locate credentials`, fix that before anything else. The rest of the workshop assumes this command succeeds.
