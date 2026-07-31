---
title: "Thiết lập AWS cục bộ (tùy chọn)"
date: 2026-07-27
weight: 10
chapter: false
pre: " <b> 5.2.10 </b> "
---

Để phát triển cục bộ mà không động vào AWS thật, dùng **MiniStack** — trình giả lập DynamoDB và S3 cục bộ — và Docker Compose. Đây là đường dẫn cục bộ tương tự job `test-go-ministack` trong `.gitlab-ci.yml`.

## Clone và cấu hình

1. Copy file môi trường mẫu:

```bash
cp .env.example .env
```

2. Sửa `.env` và điền ít nhất các giá trị sau:

```
DISCORD_CLIENT_ID=your-discord-client-id
DISCORD_CLIENT_SECRET=your-discord-client-secret
SESSION_SECRET=your-generated-session-secret
ADMIN_DISCORD_IDS=your-discord-user-id
```

3. Giữ mặc định cục bộ cho backend và storage:

```
BACKEND=dynamodb
STORAGE=s3
AWS_ENDPOINT_URL=http://localhost:4566
```

## Khởi động MiniStack

MiniStack giả lập DynamoDB và S3 trên `localhost:4566`.

```bash
docker compose up -d ministack
bash scripts/start-ministack.sh
```

`start-ministack.sh` tạo bốn bảng DynamoDB (`Config`, `Bans`, `Milestones`, `History`) và hai S3 bucket (`awsplace-canvas`, `awsplace-exports`) bên trong trình giả lập.

## Chạy stack cục bộ

Build frontend và khởi động Go server cùng nginx:

```bash
bash scripts/build-frontend.sh
docker compose up -d
```

## Kiểm tra endpoint cục bộ

```bash
curl http://localhost:8980/health
curl http://localhost:19980/
```

| Endpoint | Nội dung phục vụ |
|---|---|
| `http://localhost:8980/health` | Kiểm tra sức khỏe Go server |
| `http://localhost:19980/` | Frontend qua nginx |
| `http://localhost:19980/admin.html` | Admin dashboard |
| `http://localhost:19980/ws` | Endpoint WebSocket |

## Chạy test cục bộ

```bash
# Test Lambda
cd lambda && npm ci && npx vitest run

# Test đơn vị Go
cd go-ecs && go test ./internal/canvas/... ./internal/auth/... ./internal/ws/... -count=1

# Test tích hợp Go với MiniStack
bash scripts/start-ministack.sh
cd go-ecs && go test ./internal/ddb/... ./internal/admin/... ./internal/scheduler/... -count=1
```

## Dừng stack cục bộ

```bash
docker compose down
```

Stack cục bộ là tùy chọn. Pipeline production trong GitLab không dùng MiniStack; nó deploy lên dịch vụ AWS thật trong `ap-southeast-1`.