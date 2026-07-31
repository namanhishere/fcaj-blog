---
title: "Local AWS Setup (optional)"
date: 2026-07-27
weight: 10
chapter: false
pre: " <b> 5.2.10 </b> "
---

For local development without touching real AWS, use **MiniStack** — a local DynamoDB and S3 emulator — and Docker Compose. This is the same local path used by the `test-go-ministack` job in `.gitlab-ci.yml`.

## Clone and configure

1. Copy the example environment file:

```bash
cp .env.example .env
```

2. Edit `.env` and fill in at least these values:

```
DISCORD_CLIENT_ID=your-discord-client-id
DISCORD_CLIENT_SECRET=your-discord-client-secret
SESSION_SECRET=your-generated-session-secret
ADMIN_DISCORD_IDS=your-discord-user-id
```

3. Keep the local defaults for backend and storage:

```
BACKEND=dynamodb
STORAGE=s3
AWS_ENDPOINT_URL=http://localhost:4566
```

## Start MiniStack

MiniStack emulates DynamoDB and S3 on `localhost:4566`.

```bash
docker compose up -d ministack
bash scripts/start-ministack.sh
```

`start-ministack.sh` creates the four DynamoDB tables (`Config`, `Bans`, `Milestones`, `History`) and the two S3 buckets (`awsplace-canvas`, `awsplace-exports`) inside the emulator.

## Run the local stack

Build the frontend and start the Go server plus nginx:

```bash
bash scripts/build-frontend.sh
docker compose up -d
```

## Verify local endpoints

```bash
curl http://localhost:8980/health
curl http://localhost:19980/
```

| Endpoint | What it serves |
|---|---|
| `http://localhost:8980/health` | Go server health check |
| `http://localhost:19980/` | Frontend through nginx |
| `http://localhost:19980/admin.html` | Admin dashboard |
| `http://localhost:19980/ws` | WebSocket endpoint |

## Run local tests

```bash
# Lambda tests
cd lambda && npm ci && npx vitest run

# Go unit tests
cd go-ecs && go test ./internal/canvas/... ./internal/auth/... ./internal/ws/... -count=1

# Go integration tests with MiniStack
bash scripts/start-ministack.sh
cd go-ecs && go test ./internal/ddb/... ./internal/admin/... ./internal/scheduler/... -count=1
```

## Stop the local stack

```bash
docker compose down
```

The local stack is optional. The production pipeline in GitLab does not use MiniStack; it deploys to real AWS services in `ap-southeast-1`.
