---
title: "Application Testing"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 5.7.2. </b> "
---

Beyond infrastructure testing, the awsplace project tests the application logic itself through Go unit tests and integration tests. The GitHub Actions workflow (deploy.yml) defines **four separate test jobs** that validate the application at different layers.

#### Test jobs in the CI Pipeline

| Job Name | What It Tests | External Dependencies |
|---|---|---|
| test-lambda | Lambda function logic (Node.js) | None |
| test-go-unit | Go unit tests: canvas, auth, WebSocket, RaftDB client, migration | None |
| test-go-postgres | Go integration with PostgreSQL backend | PostgreSQL 16 service container |
| test-go-ministack | Go full integration with DynamoDB + S3 | MiniStack service container |

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

The Lambda functions are tested using Vitest. A custom **nibble-parity.js** script additionally validates data integrity properties.

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

These tests run without any external services. They cover:
- **Canvas logic** (internal/canvas/) — pixel placement rules, cooldowns, coordinate validation
- **Authentication** (internal/auth/) — Discord OAuth flow, session management
- **WebSocket handling** (internal/ws/) — message parsing, broadcasting, connection lifecycle
- **RaftDB client** (internal/store/raftdb/) — client-side retry logic, request serialization
- **Migration tool** (cmd/migrate-raftdb/) — data migration command validation

---

#### 3. PostgreSQL Integration Tests

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

This job spins up a real **PostgreSQL 16** container and runs integration tests against it. It validates:
- The PostgresBackend correctly implements the store interface
- The FilesystemStore works for local file-based storage
- SQL queries, transactions, and schema migrations work correctly

---

#### 4. MiniStack Integration Tests (DynamoDB + S3)

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
    - name: Wait for MiniStack health
      run: |
        for i in $(seq 1 60); do
          if curl -sf -o /dev/null "http://localhost:4566/_ministack/health"; then
            echo "MiniStack healthy after ${i}s"
            break
          fi
          sleep 1
        done
    - name: Create DynamoDB tables
      run: bash scripts/start-ministack.sh
    - name: Go DDB integration
      run: cd go-ecs && go test ./internal/ddb/... ./internal/admin/... ./internal/scheduler/... -count=1
    - name: Go store conformance
      run: cd go-ecs && go test -run 'TestDynamoDBBackend|TestS3Store' ./internal/store/... -count=1
    - name: Go E2E integration
      run: cd go-ecs && go test -v ./tests/integration/ -count=1
```

This is the most comprehensive application test job. It uses MiniStack — a local AWS emulator providing DynamoDB and S3 — to run full end-to-end integration tests.

Key test areas:
- **DynamoDB operations** (internal/ddb/) — table operations, query patterns, batch writes
- **Admin functionality** (internal/admin/) — administrative commands and user management
- **Scheduler** (internal/scheduler/) — timed operations like canvas snapshots
- **Store conformance** — validates that both DynamoDB and S3 backends implement the same store interface
- **E2E integration** (tests/integration/) — full end-to-end flows covering the complete request lifecycle

The health check loop waits up to 60 seconds for MiniStack to become ready before running any tests, ensuring reliable CI execution.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Navigate to your GitHub repository Actions tab.
Click on a successful "Test & Deploy" workflow run.
Expand the job list and capture all 4 test jobs showing green checkmarks.
Save as: static/images/5.6/github-test-jobs.png

Screenshot suggestion 2: Run go test -v locally.
Capture the output showing individual test function names passing.
Save as: static/images/5.6/go-unit-test-output.png
-->

---

#### 5. RaftDB Container Testing

The **raftdb-image** job in GitHub Actions performs a multi-step validation of the RaftDB Docker image:

```yaml
raftdb-image:
  steps:
    - name: Build RaftDB image once
      run: docker build --file raftdb/Dockerfile --tag "raftdb:${GITHUB_SHA}" .
    - name: Verify container contract
      run: bash raftdb/test/container_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Verify qualification client
      run: bash raftdb/test/qualification_runtime_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Verify migration and rollback
      run: bash raftdb/test/migration_runtime_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Verify S3 backup and restore
      run: bash raftdb/test/s3_runtime_contract_test.sh "raftdb:${GITHUB_SHA}"
    - name: Scan image
      uses: aquasecurity/trivy-action@v0.36.0
```

This builds the RaftDB image **once**, then runs 4 contract test scripts and a Trivy security scan against the exact same image. The vulnerability policy:
- **Critical** vulnerabilities → block publication entirely
- **High** vulnerabilities → require explicit approval via RAFTDB_ACCEPT_HIGH_CVES variable

After all tests and the scan pass, the image is published to ECR with an immutable tag (raftdb-*commit SHA*).
