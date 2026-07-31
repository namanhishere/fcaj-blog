---
title: "Proposal"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 2. </b> "
includeInReport: false
---
## What awsplace is

awsplace is a real-time collaborative pixel canvas. Every authenticated user may place one out of 16 pre-set on a single shared grid, and that pixel appears on every other connected client immediately over a WebSocket connection. The grid is not fixed: it can grow left, right, up or down, either on an administrator's command or automatically at a scheduled date, and existing artwork survives the growth

Placement is gated. Anonymous visitors may watch the canvas; placing requires a Discord login, and a per-user cooldown limits how often one account can place. Administrators, identified by a Discord user-ID allowlist, get a separate dashboard at with live statistics and canvas preview, manual board expansion, milestone management, rectangular region clear, user and IP bans, live cooldown adjustment, and a recent-activity feed.

## Who it is for

Three groups, with different needs.

**Participants** are the people drawing. They need the canvas to load in one message, to see other people's pixels without refreshing, and to be told plainly when a placement is refused and why. The WebSocket protocol serves exactly that: `INIT_DATA` carries the full grid, palette, dimensions and cooldown on connect, `PIXEL_UPDATE` carries a single changed pixel, `BOARD_RESIZE` carries new dimensions, and `ERROR` carries the refusal reason.

**Administrators** run the event. They need to grow the board, schedule future growth, remove abuse and adjust the cooldown while the event is live, without a redeployment. The ten admin routes exist for that, and every mutation is checked for a same-origin header before the admin allowlist is consulted.

**Operators**, which during this internship meant me, need to redeploy a stateful service without corrupting it, to know which exact bytes are running in production, and to reproduce the whole environment from source. That requirement is what shaped most of the infrastructure decisions in section 2.4.

## What was delivered

Two artifacts, and both are required for the project to count as finished.

The first is a **live public site** at `place.namanhishere.com`. The frontend is served by AWS Amplify Hosting; the WebSocket endpoint is `ws.place.namanhishere.com` in front of an internet-facing Application Load Balancer; the authentication and admin REST surface is `api.place.namanhishere.com` on an API Gateway HTTP API. All three hostnames resolve in Route 53 hosted zone.

The second is **reproducible infrastructure as code**. The entire environment is one CloudFormation stack, `AwsplaceStack`, synthesized from TypeScript by the AWS CDK. Nothing in production was created by hand in the console.

![awsplace deployment architecture](/images/archtechture.png)

## Project scope

**In scope**

- A real-time collaborative pixel canvas served over WebSocket, where authenticated users place one of 16 colours per cooldown interval on a shared grid
- Discord OAuth2 login flow: redirect, code exchange, HS256 JWT session cookie, `/api/me` identity endpoint
- Per-user cooldown enforcement, adjustable at runtime by administrators without redeployment
- Dynamic board expansion in four directions, triggered manually by an admin or automatically by a scheduled milestone, with existing artwork preserved through coordinate-offset shifting
- An administrator dashboard at `/admin.html` with live statistics, canvas preview, manual expansion, milestone CRUD, rectangular region clear, user and IP bans, cooldown adjustment, and a recent-activity feed
- Canvas persistence backed by RaftDB, a custom C++23 Raft-consensus storage engine with a segmented write-ahead log and periodic S3 snapshotting
- Infrastructure as code: one CDK stack (`AwsplaceStack`) in TypeScript produces every AWS resource; nothing is created by hand in the console
- CI/CD pipeline with automated unit, integration, and contract tests; Trivy image scanning; OIDC-authenticated ECR publication; and Amplify frontend deployment

**Out of scope**

- Multi-region deployment or cross-region replication
- Native mobile or desktop applications
- Authentication providers beyond Discord
- Chat, messaging, or social features
- Per-user undo or edit history for individual pixels
- Canvas export to external platforms or image-hosting services

## Functional requirements

| ID | Requirement |
|----|-------------|
| FR-01 | Anonymous visitors can view the canvas and receive live pixel broadcasts without logging in |
| FR-02 | Placing a pixel requires authentication via Discord OAuth2; unauthenticated placement attempts receive an `AUTH_REQUIRED` message over the WebSocket |
| FR-03 | Authenticated users choose from a fixed 16-colour palette and place one pixel per cooldown interval; the server validates coordinates and colour index before writing |
| FR-04 | Every accepted placement is broadcast as a `PIXEL_UPDATE` message to all connected clients |
| FR-05 | The board expands left, right, up, or down without corrupting existing artwork; growing left or up shifts all pixel coordinates via a global offset |
| FR-06 | Administrators schedule future expansions (milestones) with a trigger datetime, direction, pixel amount, and optional label; the server fires them automatically |
| FR-07 | Administrators can expand the board on demand from the dashboard |
| FR-08 | Administrators can clear a rectangular region of the canvas to white by specifying corner coordinates (superpaint) |
| FR-09 | Administrators can ban or unban users by Discord ID and by IP address; bans are checked on every placement attempt |
| FR-10 | Administrators can change the global cooldown duration at runtime via the dashboard |
| FR-11 | The admin dashboard shows a recent-activity feed with colour swatch, coordinates, Discord ID, IP address, and timestamp, auto-refreshing every 10 seconds |
| FR-12 | The admin dashboard displays live statistics: online client count, total placements, board dimensions, current cooldown, and a base64 canvas preview |
| FR-13 | A configurable event end date (`EventEndDate`) causes all placement attempts after the deadline to be rejected with a message |
| FR-14 | Canvas state, bans, milestones, and configuration persist across server restarts through RaftDB's write-ahead log and S3 snapshots |

## Non-functional requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | A placed pixel reaches every connected client within 500 ms under normal load (WebSocket broadcast over the `coder/websocket` library) |
| NFR-02 | Production availability target is 99.9 % per calendar month, supported by ECS Fargate health checks and an ALB deployment circuit breaker with automatic rollback |
| NFR-03 | Zero acknowledged-write loss on process restart: RaftDB's segmented WAL durable-acknowledges every committed entry before responding to the Go server |
| NFR-04 | The canvas supports dimensions up to 8 000 × 8 000 pixels (`MAX_DIMENSION` enforced in Go, JavaScript, and C++) |
| NFR-05 | Admin mutations require same-origin header validation (`requireSameOrigin` middleware) before the admin allowlist is consulted, defending against CSRF |
| NFR-06 | Session tokens are HS256-signed JWTs stored in httpOnly, sameSite=lax cookies scoped to the parent domain; the signing key lives in Secrets Manager and is never exposed as a plaintext environment variable |
| NFR-07 | WebSocket upgrade requests are validated against an `ALLOWED_ORIGINS` list; requests with no `Origin` header (non-browser clients) are allowed, all others are checked for an exact or subdomain match |
| NFR-08 | The entire production environment is reproducible from source: one `cdk deploy` synthesises every resource; the frontend is built and uploaded by the CI pipeline |
| NFR-09 | Each container writes to its own CloudWatch log stream (`awsplace` and `raftdb` prefixes); RaftDB exposes a CloudWatch dashboard for EFS I/O, client connections, and burst credits |
| NFR-10 | Container images are scanned by Trivy for CRITICAL and HIGH CVEs before ECR publication; critical findings block the pipeline; high findings require explicit owner acceptance recorded against the commit SHA |
| NFR-11 | The ALB idle timeout is raised to 3 600 seconds to keep long-lived WebSocket connections alive |
| NFR-12 | ECS task replacement uses `minimumHealthyPercent: 0` so the single RaftDB writer releases its EFS file lock before the replacement acquires it |

## Success criteria

| ID | Criterion | Verification |
|----|-----------|-------------|
| SC-01 | A Discord-authenticated user places a pixel and it appears on a second user's canvas in real time | Manual test with two browser sessions during staging validation |
| SC-02 | A scheduled milestone triggers a board expansion that preserves all existing pixels and broadcasts the new dimensions to connected clients | Milestone fire test in the staging stack with pre-placed artwork |
| SC-03 | An administrator can perform every dashboard action: expand, schedule milestone, delete milestone, ban user, unban user, clear region, adjust cooldown, view activity feed | Admin dashboard walkthrough on the live site |
| SC-04 | The full stack deploys from a single `cdk deploy` on the `main` branch with no manual AWS console steps | CI/CD pipeline run end-to-end |
| SC-05 | The service survives a forced ECS task restart with zero canvas data loss | Kill the running task, wait for replacement, compare canvas binary against pre-restart S3 snapshot |
| SC-06 | All automated test suites pass in CI: Go unit and integration tests, Lambda Vitest suite, nibble parity test, CDK contract tests, RaftDB address-sanitizer and thread-sanitizer presets | Green CI pipeline on `main` |
| SC-07 | The three public hostnames (`place.namanhishere.com`, `ws.place.namanhishere.com`, `api.place.namanhishere.com`) resolve over HTTPS with valid TLS certificates | Browser and `curl` verification from an external network |
| SC-08 | Every RaftDB image published to ECR carries a Trivy evidence JSON showing zero CRITICAL vulnerabilities | CI artifact retained for 90 days |

## AWS services used

The project rules require a minimum of three AWS services. **This deployment uses fifteen.** Each row below states the service's actual role in this system, taken from the CDK source and confirmed against the live account, not a generic description of the service.

| # | Service | Role in awsplace |
|---|---|---|
| 1 | Amazon ECS on AWS Fargate | Runs the single application task: two containers, `App` (Go 1.25 WebSocket and canvas server, port 8980) and `RaftDb` (the C++23 storage engine, port 9100). Task size 1024 CPU units and 2048 MiB, `desiredCount: 1` . |
| 2 | Amazon ECR | One repository, `awsplace-ecs`, holds both container images. Tag mutability is `MUTABLE_WITH_EXCLUSION` with a `raftdb-*` filter, so only the storage-engine tags are immutable; scan-on-push is enabled and the last ten images are kept . |
| 3 | Amazon EFS | The durable home of the RaftDB write-ahead log and its local snapshots. |
| 4 | Amazon S3 | A stack-owned bucket receives RaftDB engine snapshots every 300 seconds two further buckets for the canvas binary and PNG exports are imported by name rather than created . |
| 5 | AWS Lambda | A Node.js 24 Express handler that performs the Discord OAuth exchange, signs the HS256 session cookie, answers `/api/me`, and proxies admin calls to the ALB . |
| 6 | Amazon API Gateway | HTTP API v2, the public front door for `/auth/*` and `/api/*`, fronted by the custom domain `api.place.namanhishere.com` . |
| 7 | Elastic Load Balancing (ALB) | Internet-facing Application Load Balancer terminating HTTPS on 443 and forwarding to target group port 8980 with health check `/health`. Idle timeout is raised to 3600 seconds because the connections it carries are long-lived WebSockets . |
| 8 | Amazon Route 53 | Hosted zone `place.namanhishere.com`. The `api.` record is created in and the `ws.` record in; Amplify creates the apex record itself, so three hostnames are served by two CloudFormation-managed records. |
| 9 | AWS Certificate Manager | Issues the wildcard certificate, in the stack region `ap-southeast-1`, used by the `api.` and `ws.` hostnames. Amplify provisions a separate certificate for the apex. |
| 10 | AWS Secrets Manager | Holds the secret. Its only runtime reader is the ECS `App` container, which receives `SESSION_SECRET` as an ECS secret reference rather than as a plaintext environment variable. |
| 11 | AWS Amplify Hosting | Serves the built static frontend. It owns the apex DNS record and its own TLS certificate. |
| 12 | Amazon CloudWatch | Collects one log stream per container, prefixes `raftdb` and `awsplace`, and carries the Raft consensus dashboards used to watch the storage engine . |
| 13 | AWS IAM | Three roles with scoped inline policies: ECS task execution, ECS task, and Lambda execution. Section 2.5 covers the policy statements in detail. |
| 14 | AWS STS | Issues short-lived credentials to the deployment pipeline. Each credentialed CI job calls `assume-role-with-web-identity` with a GitLab-issued OIDC token and a 3600-second session. |
| 15 | AWS CloudFormation, via the CDK | The deployment substrate. One stack, `AwsplaceStack`, synthesized from TypeScript; every resource above is a member of it. |