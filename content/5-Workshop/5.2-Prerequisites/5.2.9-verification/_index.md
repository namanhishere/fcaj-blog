---
title: "Verification"
date: 2026-07-27
weight: 9
chapter: false
pre: " <b> 5.2.9 </b> "
---

Before pushing the first commit to `main`, run through this verification checklist.

## Verify tools

```bash
docker --version
docker compose version
go version
node --version
npm --version
python3 --version
npx cdk --version
aws --version
jq --version
zip --version
curl --version
git --version
```

## Verify AWS credentials

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

## Verify S3 buckets

```bash
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws s3api head-bucket --bucket "awsplace-canvas-${ACCOUNT_ID}" --region ap-southeast-1
aws s3api head-bucket --bucket "awsplace-exports-${ACCOUNT_ID}" --region ap-southeast-1
```

Both commands should exit silently with code 0.

## Verify DNS delegation

```bash
dig place.namanhishere.com NS +short
```

Expected output:

```
ns-204.awsdns-25.com.
ns-1073.awsdns-06.org.
ns-595.awsdns-10.net.
ns-1827.awsdns-36.co.uk.
```

## Verify the GitLab project path

Confirm the GitLab project is at `https://git.namanhishere.com/namanhishere/awsplace` and that the `main` branch is protected. The trust policy in section 5.2.7 only allows the `main` branch to assume the deploy role.

## Verify the GitLab CI/CD variables

In the GitLab project, go to **Settings** → **CI/CD** → **Variables** and confirm that all required variables from section 5.2.8 are present, non-empty, and correctly masked/protected.

## Pre-flight checklist

| Check | Command or location | Expected result |
|---|---|---|
| Tools installed | Section 5.2.1 verification block | All commands return version numbers |
| AWS credentials | `aws sts get-caller-identity --region ap-southeast-1` | Returns account and user ARN |
| S3 buckets | `aws s3api head-bucket` | Silent exit 0 |
| DNS delegation | `dig place.namanhishere.com NS +short` | Four Route 53 nameservers |
| Discord app | Discord Developer Portal | Two redirect URIs and `identify` scope |
| OIDC provider | IAM → Identity providers | `git.namanhishere.com` listed |
| Deploy role | IAM → Roles | `GitLabCDKDeployRole` exists with correct trust policy |
| GitLab variables | Settings → CI/CD → Variables | All required variables set and protected |
| Protected branch | GitLab → Repository → Branches | `main` is protected |

If every check passes, the repository is ready for the first production deployment. Push a commit to `main` and watch the GitLab pipeline run.
