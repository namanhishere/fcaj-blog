---
title : "CDK Project Structure"
date : 2024-01-01
weight : 4
chapter : false
pre : " <b> 5.3. </b> "
---

The CDK (AWS Cloud Development Kit) code is where all the infrastructure for **awsplace** lives. We wrote it in **TypeScript** to take advantage of strict compiler checks. It sets up everything the app needs to run: networking, compute, databases, storage, authentication, DNS, and monitoring. We've split the setup across **15 TypeScript modules** inside the **cdk/** folder, all tied together by a single main stack that deploys out to the **ap-southeast-1** (Singapore) region.

Here's a breakdown of how the project structure is organized:

| Sub-section | Description |
|---|---|
| [5.3.1 Entry Point & Stack Composition](5.3.1-entry-point/) | The main stack that links all the modules together in the right order (Includes: CDK App, AwsplaceStack, RaftDbStagingStack) |
| [5.3.2 VPC & Networking](5.3.2-vpc-networking/) | Network setup using public subnets and no NAT Gateway to save costs (Includes: VPC, subnets, security groups) |
| [5.3.3 DynamoDB Database Layer](5.3.3-database-dynamodb/) | A simple single-table design using composite keys (Includes: 4 on-demand DynamoDB TableV2s) |
| [5.3.4 ECS Fargate Compute Layer](5.3.4-ecs-compute/) | Where the Go app and RaftDB run behind an HTTPS load balancer (Includes: Fargate cluster, task definitions, ALB) |
| [5.3.5 Storage: ECR & S3](5.3.5-storage-ecr/) | Where we store Docker images and app files (Includes: ECR repository, 2 imported S3 buckets) |
| [5.3.6 IAM Roles & Security](5.3.6-iam-security/) | Setting up least-privilege permissions for the containers and Lambda (Includes: 3 IAM roles) |
| [5.3.7 Lambda, API Gateway & Amplify](5.3.7-lambda-apigw-amplify/) | Serverless auth functions and frontend hosting (Includes: Lambda, HTTP API v2, Amplify app) |
| [5.3.8 RaftDB Infrastructure & Route 53](5.3.8-raftdb-route53/) | DNS, certificates, and the RaftDB staging environment (Includes: Route 53, ACM cert, staging stack) |

#### CDK Philosophy

When writing the CDK code for awsplace, we stuck to a few core rules to keep things clean and easy to manage:

1. **Functions over classes**: Instead of messy class inheritance, each module just exports a simple **create*()** function. It takes inputs and returns exactly what it built, making the code much easier to trace.
2. **Strict TypeScript**: We turned on strict compiler checks (**strict: true**) to catch typos and missing config before you even run **cdk synth**.
3. **Export everything useful**: We make sure to output things like table names, bucket names, and ARNs as **CfnOutput** so our CI/CD pipelines can easily grab them later.
4. **Importing S3 buckets**: We don't create S3 buckets directly in the stack. Instead, we import them by name. This way, if we ever tear down the stack with **cdk destroy**, we don't accidentally delete our storage buckets.
5. **No hardcoded ARNs**: We never construct raw ARN strings by hand. We always use CDK methods, which guarantees the ARNs will be correct no matter what account or region you deploy to.
6. **Protecting critical resources**: We add **RemovalPolicy.RETAIN** to things we really don't want to lose (like our ECR repo or secrets). A simple stack deletion won't wipe out important data.

