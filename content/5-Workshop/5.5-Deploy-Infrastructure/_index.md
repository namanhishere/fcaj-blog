---
title: "Deploy Infrastructure"
date: 2024-01-01
weight: 5
chapter: false
pre: " <b> 5.5. </b> "
---

## Deploying Infrastructure with AWS CDK

The entire infrastructure for **awsplace** is managed as code using the **AWS Cloud Development Kit (CDK)**, written in TypeScript. This Infrastructure as Code (IaC) approach makes every cloud resource version-controlled, repeatable, and auditable. The whole architecture lives inside a single CDK construct called **AwsplaceStack**, which acts as the master blueprint for the application.

### High-Level Architecture

The deployed architecture is designed for scalability, security, and a clear separation of concerns. Below is a high-level overview of how the components interact with each other.

![Infrastructure Architecture](/images/archtechture.png)

The flow breaks down into three main paths:

- **Frontend path:** The user's browser resolves the domain through Route 53, which directs traffic to AWS Amplify for static content delivery.
- **Authentication path:** When a user clicks "Login", the request goes through API Gateway to a Lambda function that handles the Discord OAuth2 flow, reading the client secret from Secrets Manager at runtime.
- **Backend path:** WebSocket connections are routed through Route 53 to the Application Load Balancer, which forwards traffic to ECS Fargate tasks. Each task runs **two containers** — the Go application server and a RaftDB sidecar. In production (**raftdb-only** mode), the Go server communicates with the RaftDB sidecar via **localhost:9100** for all reads and writes. RaftDB persists its WAL and consensus data to **EFS**, and periodically writes snapshots to a dedicated **S3 Snapshot Bucket**. DynamoDB table names and S3 canvas/exports bucket names are passed as environment variables to the Go server for provisioned resources.

### The AwsplaceStack: A Deeper Look

The **AwsplaceStack** is the central CDK construct. It composes multiple smaller, modular constructs — each responsible for a specific piece of infrastructure. Below is a walk-through of every component.

#### 1. Networking

- **VPC:** A custom Virtual Private Cloud provides a logically isolated network for all resources. It spans **2 Availability Zones** for redundancy.
- **Subnets:** The VPC uses **public subnets only** with no NAT Gateways (**natGateways: 0**). This is a deliberate cost-optimization decision — all services that need outbound internet access (ECS Fargate, ALB) run in public subnets with auto-assigned public IPs. Security is enforced at the security group level rather than through network topology.

#### 2. Storage

The application uses three S3 buckets and one EFS file system:

**S3 Buckets** (imported by bucket name, not created):

- **awsplace-canvas-{account}**: Persists the primary canvas state.
- **awsplace-exports-{account}**: Stores data exports.

**RaftDB Storage** (newly created with full security configuration):

- **RaftDB Snapshot Bucket**: Versioned, encrypted (S3-managed), enforces SSL/TLS 1.2, blocks all public access. Non-current versions expire after 35 days.
- **EFS File System**: An encrypted Elastic File System provides durable, persistent storage for RaftDB consensus data. An access point scopes writes to **/raftdb/production/member-1** with restricted POSIX permissions (UID/GID 10001, mode 0750).

#### 3. Container Registry

An Amazon ECR repository named **awsplace-ecs** stores the Docker images for the Go backend server. The CI/CD pipeline pushes tagged images here, and ECS Fargate pulls them during deployment.

#### 4. IAM Roles

The stack follows the **principle of least privilege** — each service gets only the permissions it strictly needs:

- **EcsTaskRole**: Grants running tasks access to DynamoDB tables, S3 buckets, and EFS. Also includes RaftDB snapshot bucket read/write scoped to **production/member-1/*** only.
- **EcsTaskExecutionRole**: Allows the ECS agent to pull images from ECR, read secrets from Secrets Manager, and send logs to CloudWatch.
- **LambdaExecutionRole**: Grants the authentication Lambda basic execution permissions.

#### 5. Core Backend

This is the largest and most critical construct:

- **ECS Cluster**: Provides the orchestration layer for all backend containers.
- **Fargate Task Definition**: Specifies the Docker image, CPU/memory allocation, IAM roles, environment variables (table names, bucket names, domain), and secrets (injected from Secrets Manager at container startup). The task runs **two containers** — the Go application server and a RaftDB sidecar, sharing an EFS volume for consensus state.
- **Application Load Balancer (ALB)**: Sits in the public subnets, listens on both HTTP (port 80, redirects to HTTPS) and HTTPS (port 443 with wildcard TLS cert). Routes traffic to ECS tasks on port 8980. The ALB's health check path, stickiness settings, and deregistration delay are all configured for WebSocket-friendly behavior.
- **Security Groups**: The ALB security group allows HTTP/HTTPS from anywhere. The ECS security group only allows port 8980 from the ALB — no direct internet access to containers. EFS allows NFS access from the ECS security group only.
- **Route 53 A Record**: An alias record for **ws.{domainName}** points directly to the ALB.
- **Deployment Circuit Breaker**: ECS is configured with a deployment circuit breaker that automatically rolls back if new tasks fail to stabilize.

> **[SCREENSHOT: AWS ECS console showing the 'awsplace' service running and the associated tasks]**

#### 6. Authentication

- **Lambda Function**: A Node.js 24 function handles the Discord OAuth2 callback flow. It reads the client secret from **Secrets Manager** at runtime — the secret is never baked into the deployment artifact.
- **API Gateway**: An HTTP API (not REST API) maps routes under **/auth/** to the Lambda function. A custom domain **api.{domainName}** is associated with the API, using the shared wildcard ACM certificate. Route 53 records point this subdomain to the API Gateway.
- **Secrets Manager**: Stores the Discord client secret, session secret, and other sensitive configuration as a JSON object. Both the Lambda function and ECS tasks can read this secret (with IAM-scoped access).

#### 7. Frontend

- **AWS Amplify App**: Configured for **manual deployment** — no Git repository connection. The CI/CD pipeline builds the frontend and uploads a zip file directly to Amplify. This decouples frontend hosting from any specific source control provider.
- **Custom Domain**: The root domain (e.g., **place.namanhishere.com**) is mapped to the **production** branch. Amplify provisions and manages its own TLS certificate for this domain — separate from the wildcard ACM cert used by the ALB and API Gateway.
- **SPA Rewrite Rules**: A custom rewrite rule rewrites extension-less paths to **/index.html** while preserving direct access to files with extensions (CSS, JS, images) and specifically **/admin.html**. A catch-all 404 rewrite also serves **/index.html** for unknown paths.

#### 8. DNS & Certificates

- **Hosted Zone**: The stack imports an existing Route 53 hosted zone by ID (not created from scratch).
- **Wildcard ACM Certificate**: A certificate for **\*.{domainName}** is provisioned and validated via DNS. This cert is shared by the ALB (for **ws.** subdomain) and API Gateway (for **api.** subdomain). Amplify manages its own separate cert for the root domain.

#### 9. CloudWatch Dashboard

A CloudWatch dashboard is automatically provisioned with operational metrics for the ECS service, ALB, DynamoDB tables, and Lambda function. This gives the team a single-pane-of-glass view for monitoring the application health in production.

---

### The CI/CD Deployment Process

The deployment logic, orchestrated by GitHub Actions in the **deploy** job, follows a precise sequence to bring the infrastructure online safely.

1. **Environment Validation:** The process starts with **scripts/validate-deploy-env.sh**, which verifies that all required secrets and configuration variables (like **DISCORD_CLIENT_ID**, **HOSTED_ZONE_ID**, **RAFTDB_IMAGE_DIGEST**) are present and correctly formatted. If anything is missing, the pipeline fails immediately — no partial deployments.

2. **Stack Preparation:** **scripts/prepare-cloudformation-deploy.sh** inspects the CloudFormation stack's current state. If it finds a failed or rolled-back state (like **CREATE_FAILED** or **ROLLBACK_COMPLETE**), it automatically deletes the broken stack so CDK can attempt a fresh deployment. If the stack is in **UPDATE_ROLLBACK_FAILED**, it refuses to continue — that situation requires manual intervention.

3. **CDK Deploy:** With the environment validated, the core command is executed:

**npx cdk deploy --require-approval never --no-strict --all --import-existing-resources**

CDK synthesizes the TypeScript constructs into a CloudFormation template and deploys all resources. The **--import-existing-resources** flag allows CDK to re-adopt resources with explicit physical names if the stack was recreated after a failure.

> ![AwsplaceStack in CloudFormation](/images/5-Workshop/5.5-Deploy-Infrastructure/Screenshot%202026-07-27%20194430.png)

4. **Amplify Frontend Deployment:** Once backend infrastructure is stable, the pipeline packages the static assets from **dist/** into a zip file and uploads them directly to Amplify via pre-signed S3 URL. (This process is covered in detail in the next section.)

5. **ECS Service Update:** Finally, **aws ecs update-service --force-new-deployment** triggers a rolling update. ECS drains old tasks and launches new ones with the updated Docker image and configuration. The deployment circuit breaker ensures automatic rollback if the new tasks fail to stabilize.