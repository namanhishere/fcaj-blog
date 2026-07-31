---
title: "Prerequisites"
date: 2026-07-27
weight: 2
chapter: false
pre: " <b> 5.2. </b> "
---

This workshop deploys the **awsplace** r/place clone to AWS through **GitLab CI** running on a self-hosted runner at `https://git.namanhishere.com/namanhishere/awsplace`. Every AWS resource is created in the `ap-southeast-1` region.

The prerequisites below are organized into eleven sub-sections. Work through them in order before pushing a commit to the `main` branch of the GitLab repository. Several steps — especially the imported S3 buckets, the Route 53 hosted zone, and the GitLab OIDC role — are easy to skip but cause confusing late-stage failures if they are missing. The last two sections describe optional practices: a local development path with MiniStack, and a CLI sandbox for safe AWS/CDK operations.

| Sub-section | Description |
|---|---|
| [5.2.1 Software](5.2.1-software/) | Required tools, versions, and verification commands for the workstation and CI/CD pipeline |
| [5.2.2 AWS Account](5.2.2-aws-account/) | Choosing an AWS account, region lock to `ap-southeast-1`, and AWS CLI v2 login |
| [5.2.3 IAM Permissions](5.2.3-iam-permissions/) | Local deploy principal permissions and GitLab CI OIDC deploy role trust policy |
| [5.2.4 Required AWS Resources](5.2.4-required-aws-resources/) | CDK bootstrap, S3 bucket creation, and the resources the CDK stack creates for you |
| [5.2.5 Setup Discord Application](5.2.5-setup-discord-application/) | Discord Developer Portal, OAuth2 redirect URIs, `identify` scope, and admin access |
| [5.2.6 Config subdomain to Route53 from Cloudflare](5.2.6-config-subdomain-to-route53-from-cloudflare/) | Route 53 hosted zone, Cloudflare NS delegation, and DNS propagation verification |
| [5.2.7 Setup OIDC with self-hosted GitLab Runner](5.2.7-setup-oidc-with-selfhost-gitlab-runner/) | IAM OIDC provider, `GitLabCDKDeployRole`, trust policy, and OIDC flow testing |
| [5.2.8 Environment Variables — Setup with GitLab](5.2.8-environment-variables-setup-with-gitlab/) | GitLab CI/CD variables, masked/protected settings, and validation script |
| [5.2.9 Verification](5.2.9-verification/) | Pre-flight checklist for tools, credentials, S3 buckets, DNS, and GitLab variables |
| [5.2.10 Local AWS Setup](5.2.10-local-aws-setup/) | Optional MiniStack + Docker Compose local development environment |
| [5.2.11 CLI Sandbox Safety](5.2.11-cli-sandbox-safety/) | Optional Docker sandbox for safe, isolated CDK/AWS CLI operations |

Sections **5.2.1** through **5.2.9** are required for the production GitLab deployment. Sections **5.2.10** and **5.2.11** are optional but strongly recommended for local development, debugging, and safe CLI operations.

For details on what the pipeline does after these prerequisites are met, see the [CI/CD Pipeline](../5.4-CICD-Pipeline/) section.
