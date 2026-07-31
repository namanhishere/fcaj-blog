---
title: "CI/CD Pipeline"
date: 2024-01-01
weight: 4
chapter: false
pre: " <b> 5.4. </b> "
---

## CI/CD Pipeline

awsplace runs a **dual CI setup**: GitHub Actions serves as the **primary** CI/CD platform, while GitLab CI operates as a **parity mirror**. Both pipelines share the same stages, the same scripts, and — most importantly — the same security posture. Neither platform stores long-lived AWS credentials. Every pipeline run obtains short-lived AWS credentials through **OIDC** (OpenID Connect), which expire after one hour.

The diagram below shows the full lifecycle from a developer's **git push** all the way to a verified production deployment.

![CI/CD Pipeline Architecture](/images/5-Workshop/5.4-CICD-Pipeline/cicd-pipeline.png)

> **Pipeline Execution Graph:** Below is an actual execution run of the GitLab CI pipeline showing all 14 jobs passing across the 4 stages (**build-ci-image**, **test**, **build**, **deploy**).

![GitLab CI Pipeline Execution](/images/5-Workshop/5.4-CICD-Pipeline/98e24f05-f52d-4bcb-a308-0133be4483b0.jpg)

---

### 1. Code Commit and CI Triggers

The pipeline starts when a developer pushes code to the repository:

| Event | GitHub Actions | GitLab CI |
|-------|---------------|-----------|
| Push to **main** | Triggers full pipeline (test, build, deploy) | Same behavior |
| Pull Request / Merge Request | Triggers test stage only | Triggers test stage only |
| Tag pushed | Triggers build + GHCR publish + GitHub Release | Triggers build + GitLab Release |

GitHub is the primary repository. A mirror sync pushes commits to the self-hosted GitLab instance at **git.namanhishere.com**, which triggers the GitLab CI pipeline independently.

A separate dedicated workflow (**raftdb-ci.yml**) handles the RaftDB C++ component. It triggers only when files under **raftdb/** change and runs four sanitizer lanes (ASan, UBSan, TSan, Release) plus a libFuzzer smoke test. GitHub Actions is authoritative for this workflow — the GitLab mirror follows for parity.

---

### 2. OIDC Authentication — No Static Credentials

Both CI platforms authenticate to AWS using **OIDC federation** instead of storing IAM access keys as secrets. The flow works like this:

1. The CI platform generates a signed JWT token that identifies the pipeline run, the repository, and the branch.
2. This token is exchanged with AWS STS via **AssumeRoleWithWebIdentity** for temporary credentials — an access key, secret key, and session token.
3. The temporary credentials expire after one hour. No long-lived keys exist anywhere in the CI configuration.

**GitHub Actions** uses the official **aws-actions/configure-aws-credentials@v4** action:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ap-southeast-1
```

**GitLab CI** uses its built-in **id_tokens** mechanism:

```yaml
id_tokens:
  AWS_JWT_TOKEN:
    aud: https://git.namanhishere.com
```

The token is then exchanged manually:

```bash
ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity \
  --role-arn ${AWS_ROLE_ARN} \
  --role-session-name "GitLabCI-${CI_PIPELINE_ID}" \
  --web-identity-token ${AWS_JWT_TOKEN} \
  --duration-seconds 3600 \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $3}')
```

Both platforms assume the same IAM role (**AWS_ROLE_ARN**). The role's trust policy restricts which OIDC providers and which repositories can assume it.

This is a security best practice recommended by both AWS and GitHub — there are zero static AWS credentials stored in any CI platform's secret store.

> **AWS IAM OIDC Provider:** The OpenID Connect identity provider configured in AWS IAM for **git.namanhishere.com**:

![AWS IAM OpenID Connect Provider](/images/5-Workshop/5.4-CICD-Pipeline/31fe64fd-ac46-44c4-bbe9-2ec0d4945367.jpg)

> **Protected & Masked CI/CD Variables:** Application configuration and the **AWS_ROLE_ARN** are securely configured as protected and masked variables in GitLab CI:

![GitLab Protected and Masked CI/CD Variables](/images/5-Workshop/5.4-CICD-Pipeline/844cf6a4-2878-463d-b334-f46543ba1a63.jpg)

---

### 3. Test Stage — Comprehensive Test Matrix

All tests run in parallel during the test stage. The pipeline requires every test job to pass before it proceeds to build or deploy. Here is the complete test matrix:

#### Lambda Tests (Node.js)

| Job | Runtime | What It Tests |
|-----|---------|--------------|
| **test-lambda** | Node.js 24 | Vitest unit tests for the authentication Lambda (46 test cases) + nibble-parity cross-language verification |

The **nibble-parity** test deserves special attention — it verifies that the Node.js Lambda and the Go ECS server produce byte-identical canvas encoding. Since both runtimes write to the same DynamoDB table and S3 bucket, a single encoding disagreement would corrupt the shared canvas.

#### Go Server Tests

| Job | Runtime | Services | What It Tests |
|-----|---------|----------|--------------|
| **test-go-unit** | Go 1.25 | None | Canvas logic, auth middleware, WebSocket handlers — pure unit tests with no external dependencies |
| **test-go-postgres** | Go 1.25 | PostgreSQL 16 | PostgreSQL backend storage conformance + filesystem store tests |
| **test-go-ministack** | Go 1.25 | MiniStack (DynamoDB + S3 emulator) | DynamoDB backend, S3 storage, admin API, scheduler, full E2E integration tests |

The MiniStack job is the most thorough — it spins up a local AWS emulator, provisions DynamoDB tables and S3 buckets using **scripts/start-ministack.sh**, and runs end-to-end integration tests that exercise the same code path production uses.

#### CDK Infrastructure Tests

| Job | Runtime | What It Tests |
|-----|---------|--------------|
| **test-cdk** | Node.js 24 | TypeScript compilation, CDK synthesis via **cdk synth**, RaftDB workflow tests, deploy configuration contract tests, deployment contract tests |

These tests synthesize the CloudFormation template without deploying anything. They catch misconfigurations (wrong resource properties, missing outputs, incorrect dependency ordering) before a deployment attempt.

#### RaftDB Tests

| Job | Runtime | What It Tests |
|-----|---------|--------------|
| **raftdb-image** | Docker 27 | Builds the RaftDB Docker image, runs container contract tests, qualification tests, migration tests, S3 backup/restore tests, and a Trivy vulnerability scan |
| **test-raftdb-fuzz** | Clang 19 | libFuzzer smoke test on the TCP frame parser (300 seconds) |

The **raftdb-image** job is security-critical. After building the image, it runs Trivy to scan for vulnerabilities. If any **CRITICAL** vulnerability is found, the pipeline fails immediately and the image is not published. **HIGH** severity findings also block the pipeline unless the repository variable **RAFTDB_ACCEPT_HIGH_CVES** is set to the current commit SHA — this requires explicit owner acknowledgment.

After scanning, the job records a **raftdb-image-evidence.json** file containing the commit SHA, Docker image ID, and scan results. This evidence artifact travels with the image through every subsequent stage.

---

### 4. Build Stage — Docker Images and Chain-of-Custody

Once all tests pass, the build stage constructs Docker images and pushes them to container registries.

#### Go Server Image (Standard Path)

The Go server image follows a straightforward build-and-push flow:

1. Build: **docker build -t awsplace-ecs -f go-ecs/Dockerfile go-ecs** — multi-stage Alpine build producing a minimal binary
2. Tag: Image tagged with the commit SHA and **latest**
3. Push to ECR: The **scripts/push-ecs-image.sh** script handles ECR login, tagging, pushing, and digest verification — it confirms the pushed image digest matches what was built locally

The ECR repository (**awsplace-ecs**) is created automatically by **scripts/ensure-ecr-repository.sh** if it doesn't exist. The script also configures:
- Scan on push — every image pushed to ECR is automatically scanned for vulnerabilities
- Lifecycle policy — only the 10 most recent images are kept; older images are automatically expired
- Immutable tag exclusion — tags matching **raftdb-*** are immutable (cannot be overwritten), ensuring reproducibility

#### RaftDB Image (Chain-of-Custody Path)

The RaftDB image follows a stricter chain-of-custody protocol. The goal is to guarantee that the image published to ECR is byte-identical to the image that passed all tests and security scans:

1. **Build + Test + Scan** (no AWS credentials): The **raftdb-image** job builds the image, runs contract tests, qualification tests, migration tests, and a Trivy scan — all without any cloud credentials. The tested image is exported as a Docker tarball via **docker save** and passed as a CI artifact along with an evidence JSON file. These artifacts expire after 1 day — they only need to survive long enough for the publish job to consume them in the same pipeline run.

2. **Verify Identity**: The **publish-raftdb-image** job downloads the tarball, loads it with **docker load**, and verifies that the Docker image ID matches the one recorded in the evidence file. If the IDs don't match, the pipeline fails — someone tampered with the artifact.

3. **OIDC Authentication**: Only after identity verification does the job assume the AWS role. This ensures that no AWS credentials are available during the build or test phase.

The structural implementation of this dependency (**raftdb-image** → **publish-raftdb-image**) on GitHub Actions:

```yaml
publish-raftdb-image:
  needs: raftdb-image
  if: github.ref == 'refs/heads/main'
  permissions:
    id-token: write       # OIDC token minted ONLY in this job
    contents: read
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: raftdb-image-${{ github.sha }}
    # Verify image identity BEFORE exchanging OIDC token
    - name: Load and verify tested image identity
      run: |
        EXPECTED_IMAGE_ID=$(jq -r '.imageId' raftdb-image-evidence.json)
        docker load --input raftdb-image.tar
        ACTUAL_IMAGE_ID=$(docker image inspect "raftdb:${GITHUB_SHA}" --format '{{.Id}}')
        if [ "$ACTUAL_IMAGE_ID" != "$EXPECTED_IMAGE_ID" ]; then
          echo "Loaded image ID does not match tested image evidence" >&2
          exit 1
        fi
    # Only now: exchange OIDC token for AWS credentials
    - uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: ap-southeast-1
```

4. **Immutable Tagging**: The image is tagged **raftdb-<commit-sha>** and pushed to ECR. If a tag already exists, the job pulls the existing image and verifies its image ID matches — it refuses to overwrite a tag pointing to a different image.

5. **Post-push Contract Test**: After pushing, the job clears its local Docker cache, pulls the image back by digest (not by tag), and re-runs the container contract tests. This confirms the image survives a round-trip through ECR without corruption.

6. **Evidence Recording**: A **raftdb-publish-evidence.json** is saved with the ECR repository URI and digest. The deploy stage consumes this evidence to verify the image it's deploying.

It is worth noting that if the Trivy scan finds any CRITICAL vulnerability, the image will not be published and the pipeline will halt. For HIGH severity findings, the repository owner must explicitly accept them by setting **RAFTDB_ACCEPT_HIGH_CVES** to the current commit SHA.

#### Lambda Image

The Lambda authentication handler is also containerized:

```bash
docker build -t awsplace-lambda -f Dockerfile .
```

This image bundles **index.js** and the **lambda/** directory on a **node:24-alpine** base. It is pushed to both GHCR (for public access) and the GitLab Container Registry (for parity).

#### Release Creation

When a tag is pushed:

- On GitHub, the **build-push** job builds both images, pushes them to GHCR with semantic tags (**sha-**, branch name, **latest**), and creates a GitHub Release with auto-generated release notes.
- On GitLab, the **create-release** job creates a GitLab Release via **release-cli**.

---

### 5. Deploy Stage — CDK, Amplify, and ECS

The deploy stage only runs on the **main** branch and only after all test and build jobs succeed. It consists of several substeps executed sequentially.

#### Step 1: Environment Validation

Before touching any AWS resources, the pipeline runs **scripts/validate-deploy-env.sh**. This script checks that all required deployment variables are set and properly formatted:

| Variable | Validation |
|----------|-----------|
| **SESSION_SECRET** | Must be set, not an unresolved **${}** reference |
| **DISCORD_CLIENT_ID** | Must be set |
| **DISCORD_CLIENT_SECRET** | Must be set |
| **DISCORD_REDIRECT_URI** | Must be set |
| **ADMIN_DISCORD_IDS** | Must be set |
| **FRONTEND_URL** | Must be set |
| **HOSTED_ZONE_ID** | Must match pattern **Z[A-Z0-9]+** (valid Route 53 zone ID) |
| **RAFTDB_IMAGE_DIGEST** | Must match **sha256:[64 hex chars]** — ensures it came from a tested image |

If any variable is missing, contains an unresolved reference, or fails format validation, the pipeline stops before assuming the AWS role.

#### Step 2: CloudFormation Stack Preparation

**scripts/prepare-cloudformation-deploy.sh** inspects the current state of the **AwsplaceStack** CloudFormation stack and handles edge cases:

| Stack Status | Action |
|-------------|--------|
| **CREATE_FAILED**, **ROLLBACK_COMPLETE**, **ROLLBACK_FAILED**, **DELETE_FAILED** | Automatically delete the stack (up to 2 attempts) so CDK can recreate it |
| **DELETE_IN_PROGRESS** | Wait for deletion to complete |
| **UPDATE_ROLLBACK_FAILED** | Refuse to proceed — manual intervention required |
| **\*_IN_PROGRESS** | Refuse to proceed — another operation is running |
| Any stable state | Proceed with deployment |

This prevents CDK from encountering an undeployable stack state and producing confusing errors.

#### Step 3: CDK Deploy

The core deployment command:

```bash
npx cdk deploy --require-approval never --no-strict --all --import-existing-resources
```

Key flags:
- **--require-approval never** — automated deployment, no human confirmation prompts
- **--no-strict** — tolerate non-critical CDK synthesis warnings
- **--import-existing-resources** — re-adopt resources with explicit physical names if the stack was recreated after a failure

This deploys all AWS resources in dependency order: VPC, DynamoDB tables, S3 buckets, ECR, Secrets Manager, API Gateway, Lambda, ALB, ECS Fargate, CloudFront, Route 53, and Amplify.

#### Step 4: Frontend Deployment via Amplify

After CDK completes, the pipeline deploys the frontend to AWS Amplify Hosting using a direct asset upload approach (not a Git-based build):

1. Read the **AmplifyAppId** and **AmplifyBranchName** from CloudFormation stack outputs
2. Build the frontend with **bash scripts/build-frontend.sh** — this injects brand tokens into the HTML templates and copies static assets to **dist/**
3. Zip the **dist/** directory
4. Call **aws amplify create-deployment** to get a pre-signed S3 upload URL
5. Upload the zip via **curl**
6. Call **aws amplify start-deployment** to trigger the deployment
7. Poll **aws amplify get-job** every 10 seconds until the deployment succeeds (with a 10-minute timeout)

#### Step 5: ECS Force Deployment

After the frontend is live, the pipeline restarts the ECS Fargate service to pick up the new Go server image and any updated secrets:

```bash
aws ecs update-service --force-new-deployment \
  --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME"
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
```

The **wait services-stable** command blocks until the new task definition is running, healthy, and the old tasks have drained. If ECS cannot stabilize the service (for example, the new container keeps crashing), the deployment circuit breaker rolls back to the previous version automatically.

After stabilization, the pipeline prints a summary table showing the desired count, running count, and rollout state of the PRIMARY deployment.

#### Step 6: Post-Deploy Verification

The final step is a smoke test that verifies the WebSocket endpoint is reachable and correctly configured:

```bash
node scripts/check-websocket-origin.mjs \
  "wss://ws.${DOMAIN_NAME}/ws" \
  "https://${DOMAIN_NAME}"
```

This script performs a full WebSocket upgrade handshake (TLS, HTTP 101, Sec-WebSocket-Accept verification) with the correct Origin header. If the handshake fails — because of a DNS misconfiguration, a missing ALB target, or an incorrect origin policy — the pipeline reports the failure immediately rather than leaving a broken deployment in production.

---

### 6. CI Utilities Docker Image

GitLab CI requires a custom runner image (**ci-utils**) for the deploy stage, since the standard Node.js or Go images don't include all the tools needed. The image is defined in **Dockerfile.ci-utils** and includes:

| Tool | Purpose |
|------|---------|
| Node.js 24 | CDK synthesis and frontend build |
| Go 1.25 | Building the Go ECS server |
| AWS CLI v2 | All AWS API calls (STS, ECR, ECS, CloudFormation, Amplify) |
| Docker CLI | Building and pushing container images |
| jq | JSON processing for evidence files and stack outputs |
| zip/unzip | Amplify frontend asset packaging |

This image is rebuilt automatically when **Dockerfile.ci-utils** or **.gitlab-ci.yml** changes, tagged with both the commit SHA and **main**, and pushed to the GitLab Container Registry.

GitHub Actions doesn't need this image because its **ubuntu-latest** runners come with most tools pre-installed, and the pipeline uses setup actions (**actions/setup-node**, **actions/setup-go**, **actions/setup-python**) for the rest.

---

### 7. Caching Strategy

Both pipelines use dependency caching to reduce build times.

GitLab CI uses a shared cache keyed by branch:

```yaml
cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - lambda/node_modules/
    - cdk/node_modules/
    - /go/pkg/mod/
  policy: pull-push
```

GitHub Actions relies on action-level caching built into **actions/setup-node** and **actions/setup-go**, which automatically cache **node_modules** and **$GOPATH/pkg/mod** based on lockfile hashes.

Jobs that interact with Docker (image builds, scans) explicitly disable caching (**cache: []** on GitLab) to avoid cache pollution — Docker layers are ephemeral and shouldn't persist between runs.

---

### 8. Setup & Configuration Guide

Before the CI/CD pipeline can deploy to AWS, four prerequisites must be configured manually:

#### Step 1: Create an IAM OIDC Identity Provider

Both CI platforms (GitHub Actions and GitLab CI) authenticate to AWS via OIDC. An IAM Identity Provider must be created for each platform:

- **GitHub Actions**: Create an OpenID Connect provider with provider URL **https://token.actions.githubusercontent.com** and audience **sts.amazonaws.com**.
- **GitLab CI**: Create an OpenID Connect provider with your GitLab instance URL (e.g. **https://git.namanhishere.com**) and audience matching the same URL.

Then create an IAM Role with a trust policy that restricts access to specific repositories and branches. Both platforms assume the same role (**AWS_ROLE_ARN**), and the role must have permissions for ECS, ECR, S3, DynamoDB, CloudFormation, Amplify, Secrets Manager, and other services used in the stack.

#### Step 2: Domain Delegation to Route 53

The project uses a subdomain (e.g. **place.namanhishere.com**) managed by AWS Route 53 for DNS. If your root domain is managed by an external DNS provider (such as Cloudflare), you need to delegate the subdomain to Route 53 by adding **NS records** pointing to the AWS name servers.

Below is an example of the NS record configuration on Cloudflare, delegating **place.namanhishere.com** to Route 53:

![Domain Delegation — NS Records on Cloudflare](/images/5-Workshop/5.4-CICD-Pipeline/753747574_1015957567992787_6550916551567091605_n.jpg)

You can verify the NS record resolution and domain delegation from your terminal using `dig place.namanhishere.com NS`:

![DNS NS Record Resolution Check via dig](/images/5-Workshop/5.4-CICD-Pipeline/756430488_3121594578036333_8322272973070305772_n.png)

The four NS records point to the AWS Route 53 name servers assigned to the hosted zone. Once propagated, Route 53 has full authority over all DNS records under the subdomain (A records for ALB, API Gateway, Amplify, ACM certificate validation, etc.).

The **HOSTED_ZONE_ID** from Route 53 is a required CI/CD variable — the deploy script validates its format (must start with **Z** followed by alphanumeric characters) before running CDK deploy.

#### Step 3: Configure CI/CD Variables

The deploy stage requires the following variables to be set as **protected** and **masked** secrets in your CI platform:

| Variable | Description |
|----------|-------------|
| **AWS_ROLE_ARN** | ARN of the IAM role to assume via OIDC |
| **DOMAIN_NAME** | The subdomain managed by Route 53 (e.g. **place.namanhishere.com**) |
| **HOSTED_ZONE_ID** | Route 53 hosted zone ID for the subdomain |
| **SESSION_SECRET** | Random 96-character hex string for session encryption |
| **DISCORD_CLIENT_ID** | Discord OAuth2 application client ID |
| **DISCORD_CLIENT_SECRET** | Discord OAuth2 application client secret |
| **DISCORD_REDIRECT_URI** | OAuth2 callback URL (e.g. **https://api.place.namanhishere.com/auth/callback**) |
| **ADMIN_DISCORD_IDS** | Comma-separated Discord user IDs for admin access |
| **FRONTEND_URL** | Public URL of the frontend (e.g. **https://place.namanhishere.com**) |

The deploy script (**scripts/validate-deploy-env.sh**) checks that all required variables are set and non-empty before any AWS resources are touched. It also validates that **HOSTED_ZONE_ID** matches the Route 53 format and **RAFTDB_IMAGE_DIGEST** is a valid SHA-256 digest.

#### Step 4: First Deployment

Once the prerequisites are in place, push a commit to the **main** branch. The pipeline will:

1. Run all tests in parallel (Lambda, Go unit/Postgres/MiniStack, CDK, RaftDB)
2. Build and push Docker images (Go server to ECR, RaftDB with chain-of-custody verification)
3. Run **cdk deploy** to provision the entire AWS stack (VPC, DynamoDB, S3, ECS, ALB, API Gateway, Lambda, Amplify, Route 53, Secrets Manager)
4. Deploy the frontend to Amplify via direct asset upload
5. Force a new ECS deployment to pick up the latest image and secrets
6. Run a post-deploy smoke test to verify the WebSocket endpoint

The first deployment typically takes 15–20 minutes as CloudFormation creates all resources from scratch. Subsequent deployments are faster as only changed resources are updated.

---

### 9. Summary

The awsplace CI/CD pipeline ensures that every commit to **main** goes through a rigorous process before reaching production:

1. Parallel tests covering every component — Lambda (Node.js), Go server (unit + Postgres + MiniStack integration), CDK infrastructure, RaftDB (contract + security scan + fuzzing)
2. OIDC-only authentication with no static AWS credentials anywhere
3. Chain-of-custody for the RaftDB image — build, test, scan, and publish are separated into distinct jobs with cryptographic verification at each handoff
4. Environment validation before any AWS resources are touched
5. Infrastructure-as-Code deployment via CDK with automatic stack recovery for failed states
6. Frontend deployment via Amplify direct asset upload with polling and timeout
7. ECS rolling deployment with circuit breaker rollback
8. Post-deploy smoke test verifying the WebSocket endpoint from the browser's perspective

This design means a broken commit cannot silently reach production — every gate must pass, every image must be verified, and the deployed service must prove it's working before the pipeline reports success.