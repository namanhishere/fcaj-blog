---
title: "Software"
date: 2026-07-27
weight: 1
chapter: false
pre: " <b> 5.2.1 </b> "
---

The pipeline uses a mixture of Docker-based and shell-based jobs. You need the tools below on the workstation you use to inspect the repository, configure AWS, and debug the pipeline.

## Development tools

These are the languages and runtimes used directly by the application:

| Tool | Version needed | Verify with | Why it is needed |
|---|---|---|---|
| Docker Engine | Any current release that can run `docker build` | `docker --version` | Builds the Go ECS image, the Lambda image, and the RaftDB image (`awsplace/raftdb/Dockerfile`, `awsplace/go-ecs/Dockerfile`, `awsplace/Dockerfile`) |
| Docker Compose | v2, invoked as `docker compose` | `docker compose version` | Starts the local MiniStack, Go server, nginx, and RaftDB sidecar (`awsplace/docker-compose.yml`, `awsplace/docker-compose.ministack.yml`) |
| Go | 1.25 or newer | `go version` | `awsplace/go-ecs/go.mod` declares `go 1.25.0`; the CI image installs `go1.25.0` |
| Node.js | 24 or newer | `node --version` | `awsplace/lambda/package.json` requires `>=24.0.0`; the CI image is `node:24-bookworm` |
| npm | Bundled with Node 24 | `npm --version` | Installs CDK and Lambda dependencies |
| Python | 3.12 | `python3 --version` | Canvas exporters in `awsplace/export/` and the PDF report generation |
| git | Any current release | `git --version` | The container image tag is the commit SHA |

## CI/CD pipeline tools

These tools are used by the GitLab runner and by you when debugging the pipeline:

| Tool | Version needed | Verify with | Why it is needed |
|---|---|---|---|
| AWS CLI | v2 | `aws --version` | `awsplace/Dockerfile.ci-utils` installs the official AWS CLI v2; used for OIDC exchange, ECR, ECS, CloudFormation, Amplify, S3, Route 53 |
| AWS CDK CLI | v2 | `npx cdk --version` | `awsplace/Dockerfile.ci-utils` installs `aws-cdk` globally; synthesizes the CloudFormation template |
| jq | Any current release | `jq --version` | Reads stack outputs, parses evidence files, and extracts the RaftDB image digest |
| zip and unzip | Any current release | `zip --version` | The Amplify asset deploy uploads `dist/` as a zip archive |
| curl | Any current release | `curl --version` | Uploads the frontend zip to a presigned S3 URL with `curl --upload-file` |

## Optional C++ toolchain

| Tool | Version needed | Verify with | Why it is needed |
|---|---|---|---|
| CMake | 3.28 or newer | `cmake --version` | `awsplace/raftdb/CMakeLists.txt` requires `cmake_minimum_required(VERSION 3.28)` |
| Ninja | Any current release | `ninja --version` | The five CMake presets in `awsplace/raftdb/` use Ninja as the generator |
| A C++23 compiler | g++ or clang++ with full C++23 | `g++ --version` | `awsplace/raftdb/CMakeLists.txt` sets `CMAKE_CXX_STANDARD 23` with `CMAKE_CXX_EXTENSIONS OFF` |

CMake, Ninja, and the C++23 compiler are only required if you build RaftDB or run its C++ test suite directly on your machine. The Docker image build in section 5.5 carries its own toolchain inside `awsplace/raftdb/Dockerfile`, so a Docker-only path skips those three.

## The `ci-utils` image

The GitLab deploy stage runs inside a custom image defined in `awsplace/Dockerfile.ci-utils`. This image is built once, tagged with the commit SHA and `main`, and pushed to the GitLab Container Registry. It contains Node.js 24, Go 1.25, the AWS CLI v2, Docker CLI, jq, zip, unzip, and curl. It is rebuilt automatically whenever `Dockerfile.ci-utils` or `.gitlab-ci.yml` changes.

You do not need to build this image manually, but the workstation you use to debug failures should have the same tools installed so you can reproduce commands locally.

## One-shot verification

Run this block to verify the required tools. Every line should print a version or a valid response.

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

If you plan to build RaftDB outside Docker, also run:

```bash
cmake --version
ninja --version
g++ --version
```
