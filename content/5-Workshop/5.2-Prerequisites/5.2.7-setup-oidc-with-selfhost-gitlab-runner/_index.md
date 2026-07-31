---
title: "Setup OIDC with self-hosted GitLab Runner"
date: 2026-07-27
weight: 7
chapter: false
pre: " <b> 5.2.7 </b> "
---

The production pipeline uses OpenID Connect to authenticate to AWS without storing long-term credentials in GitLab. This is the same security posture described in the [CI/CD Pipeline](../5.4-CICD-Pipeline/) section.

## Why OIDC?

Without OIDC, you would need to store an AWS access key and secret key in GitLab CI/CD variables. If those variables leak, an attacker has persistent access to your account. With OIDC, GitLab provides a short-lived signed JWT token for each pipeline run. AWS STS exchanges that token for temporary credentials that expire after one hour. There are no long-lived AWS credentials in GitLab.

## Step 1: Create the IAM OIDC identity provider

1. Open the IAM console.
2. Go to **Identity providers** → **Add provider**.
3. Choose **OpenID Connect**.
4. For **Provider URL**, enter `https://git.namanhishere.com`.
5. For **Audience**, enter `https://git.namanhishere.com`.
6. Click **Get thumbprint** to fetch the TLS certificate thumbprint automatically.
7. Click **Add provider**.

The screenshot below shows the IAM OIDC provider for `git.namanhishere.com` with the audience `https://git.namanhishere.com`.

![IAM OIDC provider for GitLab](/images/5-Workshop/5.2-Prerequisite/IAM_OIDC.png)

## Step 2: Create the IAM role

1. In the IAM console, go to **Roles** → **Create role**.
2. Choose **Web identity**.
3. For **Identity provider**, select `git.namanhishere.com`.
4. For **Audience**, select `https://git.namanhishere.com`.
5. For **GitLab branch**, you may need to enter `main` or leave it blank and edit the trust policy manually after creation.
6. Name the role `GitLabCDKDeployRole`.

After creation, replace the auto-generated trust policy with this JSON. Replace `ACCOUNT_ID` with your AWS account number.

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

The screenshot below shows the `GitLabCDKDeployRole` with a maximum session duration of 1 hour.

![GitLab CDK deploy role](/images/5-Workshop/5.2-Prerequisite/IAMDeployRole.png)

## Step 3: Attach the deployment policy

Attach the service-level permissions from section 5.2.3 to the role. You can use the same policy JSON listed there.

## Step 4: Test the OIDC flow

The easiest way to test the setup is to trigger a pipeline in GitLab and watch the `deploy-to-aws` job. If the role assumption fails, the job logs will show an error from `aws sts assume-role-with-web-identity`.

If you want to test manually, you need a valid GitLab OIDC JWT token. The GitLab CI job does this automatically:

```bash
ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity \
  --role-arn "arn:aws:iam::ACCOUNT_ID:role/GitLabCDKDeployRole" \
  --role-session-name "GitLabCI-test" \
  --web-identity-token "$GITLAB_JWT_TOKEN" \
  --duration-seconds 3600 \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text)
```

A successful test returns temporary credentials. A failure usually means one of these values is wrong:

- The provider URL or audience does not match GitLab.
- The trust policy `sub` condition does not match the project path or branch.
- The role ARN is incorrect.
- The GitLab JWT token is expired.

## Step 5: Store the role ARN

Copy the role ARN:

```
arn:aws:iam::ACCOUNT_ID:role/GitLabCDKDeployRole
```

Store this in the GitLab CI/CD variable `AWS_ROLE_ARN` as described in section 5.2.8.
