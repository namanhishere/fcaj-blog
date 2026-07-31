---
title : "IAM Roles & Bảo mật"
date : 2024-01-01
weight : 6
chapter : false
pre : " <b> 5.3.6 </b> "
---

#### IAM Roles

Module IAM (**createIamRoles**) tạo **3 IAM roles** tuân theo nguyên tắc đặc quyền tối thiểu. Mỗi role được giới hạn ở các quyền tối thiểu cần thiết.

```typescript
export function createIamRoles(scope: Construct, input: IamInput): IamOutput {
  const { db, storage } = input;

  // 1. ECS Task EXECUTION Role
  const ecsTaskExecutionRole = new iam.Role(scope, 'EcsTaskExecutionRole', {
    assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
  });
  // Quyền kéo ECR + CloudWatch Logs

  // 2. ECS TASK Role
  const ecsTaskRole = new iam.Role(scope, 'EcsTaskRole', {
    assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
  });
  // DynamoDB CRUD (giới hạn theo ARN bảng) + S3 đọc/ghi (giới hạn theo ARN bucket)

  // 3. Lambda EXECUTION Role
  const lambdaExecutionRole = new iam.Role(scope, 'LambdaExecutionRole', {
    assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
  });
  // DynamoDB CRUD + S3 PutObject + CloudWatch Logs

  return { ecsTaskExecutionRole, ecsTaskRole, lambdaExecutionRole };
}
```

![Sơ đồ Phân quyền IAM & Bảo mật](/images/5-Workshop/5.3-CDK-Project-Structure/iam-roles.png)

#### Role 1: ECS Task Execution Role

Role này được sử dụng bởi ECS agent (không phải ứng dụng) để:

| Dịch vụ | Hành động | Phạm vi | Mục đích |
|---------|-----------|---------|----------|
| ECR | GetAuthorizationToken, BatchCheckLayerAvailability, GetDownloadUrlForLayer, BatchGetImage | * (tất cả tài nguyên) | Kéo container image từ ECR |
| CloudWatch Logs | CreateLogStream, PutLogEvents | * (tất cả tài nguyên) | Ghi container logs vào CloudWatch |
| Secrets Manager | GetSecretValue | Giới hạn theo ARN awsplace/app-secrets | Đọc SESSION_SECRET khi khởi động container |

#### Role 2: ECS Task Role

Role này được giả định bởi container ứng dụng Go để truy cập các dịch vụ AWS:

| Dịch vụ | Hành động | Phạm vi | Mục đích |
|---------|-----------|---------|----------|
| DynamoDB | CRUD đầy đủ: GetItem, PutItem, UpdateItem, DeleteItem, Query, Scan, v.v. | **Tất cả 4 ARN bảng + ARN chỉ mục** (giới hạn qua allTableArns()) | Thao tác Config, Bans, Milestones, History |
| S3 | GetObject, PutObject, DeleteObject, ListBucket | **ARN Canvas bucket + Exports bucket** (giới hạn theo bucket cụ thể) | Tải/lưu canvas binary, tải lên xuất PNG |
| EFS | elasticfilesystem:ClientMount, elasticfilesystem:ClientWrite | Giới hạn theo ARN access point RaftDB | Gắn kết EFS cho RaftDB WAL |

**Giới hạn tài nguyên:** Quyền DynamoDB sử dụng hàm trợ giúp tạo ARN cho mỗi bảng VÀ chỉ mục của nó:

```typescript
function allTableArns(db: DatabaseOutput): string[] {
  const tables = [db.configTable, db.bansTable, db.milestonesTable, db.historyTable];
  return tables.flatMap((t) => [t.tableArn, `${t.tableArn}/index/*`]);
}
```

Điều này ngăn task truy cập bất kỳ bảng DynamoDB nào khác ngoài bốn bảng ứng dụng.

#### Role 3: Lambda Execution Role

Role này được giả định bởi hàm Lambda cho auth và admin proxy:

| Dịch vụ | Hành động | Phạm vi | Mục đích |
|---------|-----------|---------|----------|
| DynamoDB | CRUD đầy đủ (giống ECS task) | Tất cả 4 ARN bảng + ARN chỉ mục | Truy cập DynamoDB trực tiếp từ Lambda |
| S3 | PutObject | Chỉ Exports bucket | Ghi xuất PNG |
| CloudWatch Logs | Basic execution role | Managed policy AWSLambdaBasicExecutionRole | Ghi log Lambda |

**QUAN TRỌNG: Lambda KHÔNG có ec2:DescribeNetworkInterfaces** — nó **không** được gắn vào VPC. Lambda truy cập DynamoDB, S3 và ECS ALB qua các điểm cuối API công cộng của AWS. Điều này tránh hình phạt khởi động lạnh từ việc cung cấp ENI.

#### Tổng quan Kiến trúc Bảo mật

```
┌────────────────────────────────────────────────────────────────────┐
│                             AWS Cloud                              │
│                                                                    │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │    Lambda    │    │     ALB      │    │     ECS Fargate      │  │
│  │ (không VPC)  │    │  (công cộng) │    │   (public subnet)    │  │
│  │              │    │              │    │                      │  │
│  │ Role:        │    │ SG:          │    │ Container Role:      │  │
│  │ Lambda Exec  │    │ 0.0.0.0/0    │    │ - ECS Task Role      │  │
│  │              │    │ :80, :443    │    │                      │  │
│  │ Perms:       │    │              │    │ Execution Role:      │  │
│  │ - DDB CRUD   │    │              │    │ - ECS Task Exec      │  │
│  │ - S3 Put     │    │              │    │                      │  │
│  │ - CW Logs    │    │              │    │                      │  │
│  └──────┬───────┘    └──────┬───────┘    └──────────┬───────────┘  │
│         │                   │                       │              │
│         ▼                   ▼                       ▼              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                 Dịch vụ AWS (API công cộng)                  │  │
│  │                                                              │  │
│  │    DynamoDB                 S3                 Secrets Mgr   │  │
│  │    ECR                      EFS                CloudWatch    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

**Các thuộc tính bảo mật chính:**

| Thuộc tính | Triển khai |
|------------|------------|
| ECS→DynamoDB | Giới hạn chính xác theo 4 ARN bảng |
| ECS→S3 | Giới hạn chính xác theo 2 ARN bucket |
| Lambda→DynamoDB | Giới hạn chính xác theo 4 ARN bảng |
| Lambda→S3 | Chỉ ghi vào exports bucket |
| JWT secret | Không bao giờ trong mã; được kéo từ Secrets Manager khi ECS khởi động hoặc Lambda env var |
| Truy cập Secrets Manager | ECS execution role (chỉ khi khởi động), ECS task role (runtime) |
| Không VPC cho Lambda | Không ENI cold start, không cần quyền ec2:* |
