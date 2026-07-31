---
title: "CLI Sandbox Safety (optional)"
date: 2026-07-27
weight: 11
chapter: false
pre: " <b> 5.2.11 </b> "
---

The CDK CLI and AWS CLI run with powerful permissions. A single typo in a `cdk deploy` or `aws s3 rm` command on your host machine can accidentally affect other AWS projects or profiles. The awsplace repository includes a lightweight Docker sandbox in `awsplace/cdk/Dockerfile` that isolates these tools from your host environment.

This section is optional but strongly recommended for any manual CLI operation on the stack.

## Why a sandbox?

| Benefit | Explanation |
|---|---|
| **Credential isolation** | The container does not inherit the host's `~/.aws` directory. AWS sessions do not leak between host and container. |
| **Version pinning** | Everyone runs the same Node.js 24, AWS CLI v2, and CDK CLI versions, regardless of what is installed on the host. |
| **Reproducibility** | A command that works inside the sandbox works for every team member. No "works on my machine" issues. |
| **Safe experimentation** | You can run `cdk diff`, `cdk deploy`, or `cdk destroy` without worrying about accidentally hitting the wrong AWS profile on your host. |

## The Dockerfile

`awsplace/cdk/Dockerfile` is a minimal image built on `node:24-bookworm`:

```dockerfile
FROM node:24-bookworm

# AWS CLI v2
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    less \
    groff \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# AWS CDK
RUN npm install -g aws-cdk

WORKDIR /workspace

CMD ["/bin/bash"]

# Build using docker build -t aws-bootstrap -f cdk/Dockerfile .
#Lauch using docker run -it --rm -v $(pwd):/workspace -w /workspace/cdk aws-bootstrap
```

The image installs:
- **Node.js 24** (from the base image) — required by CDK and the Lambda build.
- **AWS CLI v2** — for `aws sts`, `aws s3api`, `aws ecs`, and all other AWS API calls.
- **AWS CDK CLI** — for `cdk synth`, `cdk diff`, `cdk deploy`, `cdk destroy`.
- **git, curl, unzip** — used by CDK asset staging and scripts.

No AWS credentials are baked into the image. You authenticate after starting the container.

## Build the sandbox image

From the repository root:

```bash
docker build -t aws-bootstrap -f cdk/Dockerfile .
```

This only needs to be done once. Rebuild if `Dockerfile.ci-utils` or `cdk/Dockerfile` changes.

## Run the sandbox

```bash
docker run -it --rm -v $(pwd):/workspace -w /workspace/cdk aws-bootstrap
```

Flags explained:

| Flag | Purpose |
|---|---|
| `-it` | Interactive terminal |
| `--rm` | Remove the container when it exits |
| `-v $(pwd):/workspace` | Mount the repository into the container |
| `-w /workspace/cdk` | Start in the CDK directory |

## Authenticate inside the container

The container starts with no AWS credentials. Log in from inside:

```bash
aws login
```

This opens a browser session on the host machine. After authentication, the temporary credentials live only inside the container. When the container exits, the session is gone.

This design is intentional. The container does not mount `~/.aws` from the host, so:

- The host's AWS profiles and SSO sessions are not visible inside the container.
- The container's temporary credentials do not persist on the host after exit.
- Different team members can log in with their own accounts without profile conflicts.

## Running CDK commands

Once authenticated inside the sandbox, you can run any CDK or AWS CLI command:

```bash
# Synthesize the CloudFormation template
npx cdk synth --no-strict

# Preview changes
npx cdk diff

# Deploy the stack
npx cdk deploy AwsplaceStack --require-approval never --no-strict --import-existing-resources

# Destroy the stack
npx cdk destroy AwsplaceStack
```

All commands run in `ap-southeast-1` by default (set in `awsplace/cdk/bin/app.ts`).

## Case study: Buggy AWS billing estimate (16–18 July 2026)

On 16 July 2026, AWS experienced a service issue that caused the estimated billing dashboard to display wildly inaccurate numbers. The awsplace stack showed an estimated bill of **$1,174,198,467.12** — clearly a calculation error, not an actual charge.

![AWS estimated billing showing $1.17B due to a calculation glitch](/images/5-Workshop/5.2-Prerequisite/buggyaws.png)

The team used the CLI sandbox to safely destroy the stack without affecting other AWS projects or profiles on the host machine. Running `cdk destroy` inside the container ensured the operation was isolated and the host's `~/.aws` credentials were not involved.

![cdk destroy running inside the sandbox container](/images/5-Workshop/5.2-Prerequisite/destroy.png)

The destroy succeeded, and the erroneous billing estimate was cleared once the stack resources were removed.

## Best practice

Always use the sandbox for any CDK or AWS CLI operation on the awsplace stack:

| Operation | Run inside sandbox? |
|---|---|
| `cdk diff` | Yes |
| `cdk deploy` | Yes |
| `cdk destroy` | Yes |
| `aws sts get-caller-identity` | Yes |
| `aws s3api head-bucket` | Yes |
| `aws ecs update-service` | Yes |
| `npx cdk bootstrap` | Yes |

Running these commands directly on the host risks version mismatches, credential leakage, and accidental operations on the wrong AWS profile. The sandbox eliminates these risks at the cost of a one-time Docker build.
