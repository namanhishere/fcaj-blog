---
title : "Lớp Tính toán ECS Fargate"
date : 2024-01-01
weight : 4
chapter : false
pre : " <b> 5.3.4 </b> "
---

#### ECS Fargate + ALB

Module ECS (**createEcs**) là module phức tạp nhất, định nghĩa lớp tính toán: một **ECS Fargate cluster** chạy container ứng dụng Go với **RaftDB sidecar**, được đặt trước bởi **Application Load Balancer (ALB)** với kết thúc HTTPS.

![Sơ đồ Kiến trúc ECS Fargate](/images/5-Workshop/5.3-CDK-Project-Structure/ecs-architecture.png)

#### Task Definition

Fargate task chạy **hai container** trong một task duy nhất:

| Container | Image | CPU/Bộ nhớ | Cổng | Người dùng | Mục đích |
|-----------|-------|------------|------|------------|----------|
| **RaftDB** (sidecar) | ECR (SHA256 digest) | Chia sẻ 1024/2048 | 9100 | 10001:10001 (non-root) | Raft consensus + WAL + lưu trữ canvas |
| **App** (Go server) | ECR (tagged image) | Chia sẻ 1024/2048 | 8980 | Mặc định | Máy chủ HTTP/WebSocket |

**Tài nguyên task:** 1024 CPU units (1 vCPU) / 2048 MiB bộ nhớ.

**Phụ thuộc container:** App container có phụ thuộc vào RaftDB:
```typescript
appContainer.addContainerDependencies({
  container: raftDbContainer,
  condition: ecs.ContainerDependencyCondition.HEALTHY,
});
```

App container sẽ không khởi động cho đến khi RaftDB sidecar vượt qua kiểm tra sức khỏe.

#### Cấu hình RaftDB Sidecar

```typescript
const raftDbContainer = taskDefinition.addContainer('RaftDb', {
  image: ecs.ContainerImage.fromEcrRepository(ecrRepo, raftDbImageDigest),
  user: '10001:10001',
  workingDirectory: '/data/raftdb',
  environment: {
    RAFTDB_PORT: '9100',
    RAFTDB_DATA_DIR: '/data/raftdb',
    RAFTDB_READY_FILE: '/tmp/raftdb-ready',
    RAFTDB_RESTORE_FROM_S3: 'false',
    RAFTDB_SNAPSHOT_BUCKET: raftDb.snapshotBucket.bucketName,
    RAFTDB_SNAPSHOT_PREFIX: 'production/member-1',
    RAFTDB_SNAPSHOT_INTERVAL_SECONDS: '300',
  },
  healthCheck: { ... },
  stopTimeout: Duration.seconds(120),
});
```

**Chi tiết chính:**
- **Kéo image bằng digest**: Sử dụng SHA256 digest bất biến, không phải tag có thể thay đổi. Đảm bảo image đã kiểm thử chính xác được triển khai.
- **Người dùng non-root** (10001:10001): Tuân theo các phương pháp bảo mật tốt nhất.
- **Gắn kết EFS**: Dữ liệu RaftDB (/data/raftdb) được lưu trữ trên EFS filesystem được mã hóa để đảm bảo độ bền.
- **Kiểm tra sức khỏe**: Script kiểm tra sức khỏe tùy chỉnh với khoảng thời gian 5 giây, 10 lần thử lại trước khi đánh dấu không khỏe mạnh.

#### Cấu hình App Container

```typescript
const appContainer = taskDefinition.addContainer('App', {
  image: ecs.ContainerImage.fromEcrRepository(ecrRepo, imageTag),
  portMappings: [{ containerPort: 8980 }],
  environment: {
    PORT: '8980',
    DATA_MODE: 'raftdb-only',
    BACKEND: 'raftdb',
    STORAGE: 'raftdb',
    RAFTDB_ADDR: '127.0.0.1:9100',
    AUTH_ENABLED: 'false',
    ALLOWED_ORIGINS: `https://${domainName}`,
    ...
  },
  secrets: {
    SESSION_SECRET: ecs.Secret.fromSecretsManager(appSecret, 'SESSION_SECRET'),
  },
});
```

Máy chủ Go kết nối với RaftDB qua localhost:9100 (sidecar). Nó kéo SESSION_SECRET từ Secrets Manager khi khởi động qua trường secrets.

#### Cấu hình Fargate Service

```typescript
const service = new ecs.FargateService(scope, 'Service', {
  cluster, taskDefinition,
  desiredCount: 1,
  minHealthyPercent: 0,    // Dừng trước khi thay thế
  maxHealthyPercent: 100,
  assignPublicIp: true,
  vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
  securityGroups: [ecsSg],
});
```

**Các quyết định an toàn triển khai quan trọng:**

1. **desiredCount: 1**: Triển khai một instance. RaftDB sidecar ghi vào một EFS WAL duy nhất — hai task chồng chéo sẽ làm hỏng WAL.

2. **minHealthyPercent: 0**: Task đang chạy được DỪNG TRƯỚC KHI task thay thế khởi động. Điều này ngăn hai task truy cập EFS filesystem đồng thời.

3. **maxHealthyPercent: 100**: Chỉ một task chạy tại bất kỳ thời điểm nào.

4. **Circuit breaker triển khai** (được cấu hình trên tài nguyên CloudFormation trực tiếp):
```typescript
cfnService.addPropertyOverride('DeploymentConfiguration.DeploymentCircuitBreaker', {
  Enable: true,
  Rollback: true,
});
```
Nếu triển khai thất bại, ECS tự động quay lại định nghĩa task ổn định trước đó.

5. **AZ Rebalancing bị vô hiệu hóa**: **AvailabilityZoneRebalancing: DISABLED** ngăn ECS di chuyển task giữa các AZ (điều này sẽ làm gián đoạn gắn kết EFS).

#### Cấu hình ALB

| Cài đặt | Giá trị | Lý do |
|---------|--------|-------|
| Đường dẫn kiểm tra sức khỏe | /health | Máy chủ Go phục vụ "ok" tại điểm cuối này |
| Khoảng thời gian kiểm tra | 30 giây | Tần suất cân bằng |
| Thời gian chờ | 5 giây | Đủ nhanh cho điểm cuối sức khỏe nhẹ của Go |
| Ngưỡng khỏe mạnh | 2 | Yêu cầu 2 lần thành công liên tiếp |
| Idle timeout | **3600 giây** | Cho kết nối WebSocket dài hạn (mặc định 60 giây sẽ ngắt kết nối người xem không hoạt động) |
| Chuyển hướng HTTP→HTTPS | Vĩnh viễn (301) | Tất cả lưu lượng HTTP được chuyển hướng sang HTTPS |

**Bản ghi Route 53 cho WebSocket:**
```typescript
new route53.ARecord(scope, 'WsRecord', {
  zone: hostedZone,
  recordName: `ws.${domainName}`,
  target: route53.RecordTarget.fromAlias(
    new route53_targets.LoadBalancerTarget(alb)
  ),
});
```

Điều này tạo **ws.\<domain\>** trỏ đến ALB, cho phép kiến trúc tên miền phân tách: frontend tại tên miền gốc, API tại subdomain api., WebSocket tại subdomain ws.

#### Tại sao ECS Single-Instance?

| Lý do | Giải thích |
|-------|------------|
| Quyền sở hữu RaftDB WAL | Chỉ một writer có thể sở hữu EFS WAL tại một thời điểm |
| Tối ưu chi phí | Một task là đủ cho cơ sở người dùng hiện tại |
| Đơn giản | Không cần session affinity hoặc đồng bộ trạng thái chéo task |
| Cooldowns trong bộ nhớ | Mất khi khởi động lại, nhưng không quan trọng; được tạo lại ở lần đặt tiếp theo |

**QUAN TRỌNG:** Autoscaling số lượng task ECS **bị CẤM RÕ RÀNG** đối với RaftDB voters theo anti-patterns của dự án.
