---
title: "Workshop Overview"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.1. </b> "
---

## What this workshop is

This workshop walks through every operational step required to deploy, test, monitor, and tear down **awsplace** — from a blank AWS account to a live production site. It is written for someone who wants to reproduce the entire environment from source, not just read about it. Each section corresponds to a phase in the deployment lifecycle: prerequisites, infrastructure-as-code structure, CI/CD pipeline, deployment, testing, monitoring, and cleanup.

The workshop assumes you have basic familiarity with AWS, Docker, and the command line. It does not assume prior experience with the CDK, ECS Fargate, or WebSocket servers.

## Architecture at a glance

The deployed architecture serves three traffic paths through three public hostnames, all resolved by a single Route 53 hosted zone:

| Path | Hostname | Destination | Purpose |
|---|---|---|---|
| Frontend | `place.namanhishere.com` | AWS Amplify Hosting | Static HTML, CSS, and JavaScript served through Amplify's global CDN |
| Authentication | `api.place.namanhishere.com` | API Gateway HTTP API → Lambda | Discord OAuth2 callback, session cookie signing, `/api/me` identity endpoint |
| Backend | `ws.place.namanhishere.com` | ALB → ECS Fargate | Long-lived WebSocket connections for real-time pixel broadcasts |

Every AWS resource in this architecture is created by a single `cdk deploy` command. Nothing is provisioned by hand in the console.

![Infrastructure Architecture](/images/archtechture.png)

## Workshop sections

| # | Section | What it covers |
|---|---------|----------------|
| 5.2 | [Prerequisites](5.2-Prerequisites/) | Software installation, AWS account setup, IAM permissions, Discord application, DNS delegation, OIDC configuration, environment variables, and verification |
| 5.3 | [CDK Project Structure](5.3-CDK-Project-Structure/) | The 15 TypeScript modules that compose `AwsplaceStack`: entry point, VPC networking, DynamoDB, ECS Fargate, ECR, IAM, Lambda, API Gateway, Amplify, Route 53, and RaftDB infrastructure |
| 5.4 | [CI/CD Pipeline](5.4-CICD-Pipeline/) | Dual CI setup with GitHub Actions and GitLab CI, OIDC authentication, test matrix, Docker image build with chain-of-custody, and the deploy sequence |
| 5.5 | [Deploy Infrastructure](5.5-Deploy-Infrastructure/) | Running `cdk deploy` to provision the full AWS stack, stack preparation for failed states, and the deployment flow |
| 5.6 | [Deploy Frontend](5.6-Deploy-Frontend/) | Building the static frontend with token substitution, uploading to Amplify via pre-signed S3 URL, and verifying the deployment |
| 5.7 | [Test & Validate](5.7-Test-and-Validate/) | CDK contract tests with Jest, Go unit and integration tests, and CI/CD pipeline validation |
| 5.8 | [Monitoring](5.8-Monitoring/) | CloudWatch dashboards for Raft metrics and EFS, alarms for CPU, memory, and snapshot staleness, health checks, and centralized logging |
| 5.9 | [Cleanup](5.9-Cleanup/) | Resource removal policy design, `cdk destroy` procedures, and manual cleanup of retained data |

## What you will have at the end

After completing every section in order, you will have:

- A **live public site** at your chosen domain, served by AWS Amplify Hosting, with a WebSocket endpoint behind an ALB and an authentication surface on API Gateway
- **Every AWS resource** created by a single `cdk deploy` command — nothing provisioned by hand in the console
- A **CI/CD pipeline** on both GitHub Actions and GitLab CI that tests, builds, scans, and deploys automatically on every push to `main`
- **Monitoring and alerting** through CloudWatch dashboards and alarms, all defined in CDK and tested before deployment
- A **clean teardown path** that removes the running stack without destroying retained data unless you explicitly choose to

## AWS services used

The workshop deploys across **fifteen AWS services**. Each is introduced in the section where it is first created or configured:

| # | Service | Role in awsplace | Introduced in |
|---|---|---|---|
| 1 | Amazon ECS on AWS Fargate | Runs the single application task: two containers, `App` (Go 1.25 WebSocket server) and `RaftDb` (C++23 storage engine) | 5.3 CDK Project Structure |
| 2 | Amazon ECR | One repository, `awsplace-ecs`, holds both container images with scan-on-push enabled | 5.3 CDK Project Structure |
| 3 | Amazon EFS | Durable home of the RaftDB write-ahead log and local snapshots | 5.3 CDK Project Structure |
| 4 | Amazon S3 | Snapshot bucket for RaftDB engine; imported buckets for canvas binary and PNG exports | 5.2 Prerequisites |
| 5 | AWS Lambda | Node.js 24 handler for Discord OAuth2 exchange, session cookie signing, and `/api/me` | 5.3 CDK Project Structure |
| 6 | Amazon API Gateway | HTTP API v2, public front door for `/auth/*` and `/api/*` | 5.3 CDK Project Structure |
| 7 | Elastic Load Balancing (ALB) | Internet-facing ALB terminating HTTPS, forwarding WebSocket traffic to ECS on port 8980 | 5.3 CDK Project Structure |
| 8 | Amazon Route 53 | Hosted zone for the custom domain; creates `api.` and `ws.` alias records | 5.2 Prerequisites |
| 9 | AWS Certificate Manager | Wildcard certificate for `*.domain`, shared by ALB and API Gateway | 5.3 CDK Project Structure |
| 10 | AWS Secrets Manager | Holds the Discord client secret and session signing key; never exposed as plaintext env vars | 5.3 CDK Project Structure |
| 11 | AWS Amplify Hosting | Serves the built static frontend; owns the apex DNS record and its own TLS certificate | 5.6 Deploy Frontend |
| 12 | Amazon CloudWatch | Log streams per container, Raft consensus dashboards, and operational alarms | 5.8 Monitoring |
| 13 | AWS IAM | Three roles with scoped inline policies: ECS task execution, ECS task, and Lambda execution | 5.2 Prerequisites |
| 14 | AWS STS | Short-lived credentials for the deployment pipeline via OIDC federation | 5.4 CI/CD Pipeline |
| 15 | AWS CloudFormation | Deployment substrate; one stack, `AwsplaceStack`, synthesized from TypeScript | 5.5 Deploy Infrastructure |

## Prerequisites at a glance

Before starting, you need:

| Requirement | Details |
|---|---|
| AWS account | With administrator access in `ap-southeast-1` |
| Domain | A subdomain delegated to Route 53 (e.g. `place.namanhishere.com`) |
| Discord application | OAuth2 client with `identify` scope and redirect URI pointing to your API Gateway |
| GitLab instance | Self-hosted at a known URL, with CI/CD runner configured for OIDC |
| GitHub repository | With Actions enabled and OIDC provider configured in AWS IAM |
| Software | Node.js 24+, Go 1.25+, Docker 27+, AWS CLI v2, CDK CLI |

Section [5.2 Prerequisites](5.2-Prerequisites/) covers each of these in detail, with verification commands to confirm everything is in place before you push your first commit.
