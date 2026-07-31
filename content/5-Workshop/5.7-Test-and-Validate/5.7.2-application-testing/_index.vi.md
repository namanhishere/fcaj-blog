---
title: "Kiểm thử Ứng dụng"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 5.7.2. </b> "
---

Bên cạnh kiểm thử hạ tầng, dự án awsplace còn kiểm thử logic ứng dụng thông qua Go unit test và integration test. Workflow GitHub Actions (deploy.yml) định nghĩa **bốn job test riêng biệt** để xác thực ứng dụng ở các tầng khác nhau.

#### Các job test trong CI Pipeline

| Tên Job | Nội dung test | Phụ thuộc ngoài |
|---|---|---|
| test-lambda | Logic Lambda function (Node.js) | Không có |
| test-go-unit | Go unit test: canvas, auth, WebSocket, RaftDB client, migration | Không có |
| test-go-postgres | Go integration với PostgreSQL backend | PostgreSQL 16 service container |
| test-go-ministack | Go full integration với DynamoDB + S3 | MiniStack service container |

---

#### 1. Lambda Unit Tests

```yaml
test-lambda:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with: { node-version: '24' }
    - run: cd lambda && npm ci
    - run: cd lambda && npx vitest run
    - run: node lambda/tests/nibble-parity.js
```

Các Lambda function được test bằng Vitest. Một script **nibble-parity.js** tùy chỉnh còn xác thực thêm các thuộc tính toàn vẹn dữ liệu.

---

#### 2. Go Unit Tests

```yaml
test-go-unit:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with: { go-version: '1.25' }
    - run: cd go-ecs && go test ./internal/canvas/... ./internal/auth/... ./internal/ws/... -count=1
    - run: cd go-ecs && go test ./internal/backends/... ./internal/store/raftdb/... ./internal/ws/... -count=1
    - run: cd go-ecs && go test ./cmd/migrate-raftdb/... -count=1
```

Các bài test này chạy không cần bất kỳ dịch vụ bên ngoài nào. Chúng bao gồm:
- **Canvas logic** (internal/canvas/) — quy tắc đặt pixel, cooldown, xác thực tọa độ
- **Xác thực** (internal/auth/) — Discord OAuth flow, quản lý session
- **Xử lý WebSocket** (internal/ws/) — phân tích tin nhắn, broadcasting, vòng đời kết nối
- **RaftDB client** (internal/store/raftdb/) — logic retry phía client, serialization request
- **Công cụ migration** (cmd/migrate-raftdb/) — xác thực lệnh di chuyển dữ liệu

---

#### 3. Integration test với PostgreSQL

```yaml
test-go-postgres:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
        POSTGRES_DB: awsplace
  env:
    DATABASE_URL: postgres://test:test@localhost:5432/awsplace?sslmode=disable
    BACKEND: postgres
    STORAGE: fs
  steps:
    - run: cd go-ecs && go test -run 'TestPostgresBackend|TestFilesystemStore' ./internal/store/... -count=1
```

Job này khởi tạo một container **PostgreSQL 16 thực** và chạy integration test. Nó xác thực:
- PostgresBackend triển khai đúng store interface
- FilesystemStore hoạt động cho lưu trữ file local
- Các truy vấn SQL, transaction, và schema migration hoạt động chính xác

---

#### 4. Integration test với MiniStack (DynamoDB + S3)

```yaml
test-go-ministack:
  runs-on: ubuntu-latest
  services:
    ministack:
      image: nahuelnucera/ministack
      ports: ['4566:4566']
  env:
    AWS_ENDPOINT_URL: http://localhost:4566
    BACKEND: dynamodb
    STORAGE: s3
  steps:
    - name: Chờ MiniStack sẵn sàng
      run: |
        for i in $(seq 1 60); do
          if curl -sf -o /dev/null "http://localhost:4566/_ministack/health"; then
            echo "MiniStack healthy after ${i}s"
            break
          fi
          sleep 1
        done
    - name: Tạo bảng DynamoDB
      run: bash scripts/start-ministack.sh
    - name: Go DDB integration
      run: cd go-ecs && go test ./internal/ddb/... ./internal/admin/... ./internal/scheduler/... -count=1
    - name: Go store conformance
      run: cd go-ecs && go test -run 'TestDynamoDBBackend|TestS3Store' ./internal/store/... -count=1
    - name: Go E2E integration
      run: cd go-ecs && go test -v ./tests/integration/ -count=1
```

Đây là job test ứng dụng toàn diện nhất. Nó sử dụng MiniStack — một AWS emulator local cung cấp DynamoDB và S3 — để chạy integration test đầu-cuối hoàn chỉnh.

Các khu vực test chính:
- **Thao tác DynamoDB** (internal/ddb/) — các thao tác table, query pattern, batch write
- **Chức năng Admin** (internal/admin/) — lệnh quản trị và quản lý người dùng
- **Scheduler** (internal/scheduler/) — các thao tác định thời như snapshot canvas
- **Store conformance** — xác thực cả DynamoDB và S3 backend đều triển khai cùng store interface
- **E2E integration** (tests/integration/) — luồng đầu-cuối hoàn chỉnh bao gồm toàn bộ request lifecycle

Vòng lặp health check chờ tối đa 60 giây cho MiniStack sẵn sàng trước khi chạy test, đảm bảo CI chạy ổn định.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Vào tab Actions trên GitHub repository.
Click vào một workflow run "Test & Deploy" thành công.
Mở rộng danh sách job và chụp cả 4 job test hiển thị dấu tick xanh.
Lưu tại: static/images/5.6/github-test-jobs.png

Gợi ý chụp ảnh 2: Chạy go test -v ở local.
Chụp đầu ra hiển thị tên từng test function pass.
Lưu tại: static/images/5.6/go-unit-test-output.png
-->

---

#### 5. Kiểm thử container RaftDB

Job **raftdb-image** trong GitHub Actions thực hiện xác thực nhiều bước cho Docker image RaftDB:

```yaml
raftdb-image:
  steps:
    - name: Build RaftDB image một lần
      run: docker build --file raftdb/Dockerfile --tag "raftdb:${GITHUB_SHA}" .
    - name: Kiểm tra container contract
      run: bash raftdb/test/container_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Kiểm tra qualification client
      run: bash raftdb/test/qualification_runtime_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Kiểm tra migration và rollback
      run: bash raftdb/test/migration_runtime_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Kiểm tra S3 backup và restore
      run: bash raftdb/test/s3_runtime_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Quét bảo mật image
      uses: aquasecurity/trivy-action@v0.36.0
```

Quá trình này build RaftDB image **một lần duy nhất**, sau đó chạy 4 script contract test và một bước quét bảo mật Trivy trên đúng image đó. Chính sách lỗ hổng:
- Lỗ hổng **Critical** → chặn hoàn toàn việc publish
- Lỗ hổng **High** → yêu cầu phê duyệt rõ ràng qua biến RAFTDB_ACCEPT_HIGH_CVES

Sau khi tất cả test và quét đều pass, image được publish lên ECR với tag bất biến (raftdb-*commit SHA*).
