---
title: "Centralized Logging"
date: 2024-01-01
weight: 4
chapter: false
pre: " <b> 5.8.4. </b> "
---

Mỗi container trong dự án awsplace đều truyền log đến CloudWatch Logs sử dụng **awslogs** log driver. Không có log nào tồn tại trên filesystem của container — chúng được đẩy lên CloudWatch, nơi chúng tồn tại sau khi task bị thay thế, có thể được truy vấn bằng CloudWatch Logs Insights, và được giữ lại bởi chính sách retention của log group. Chiến lược logging sử dụng stream prefix chuyên dụng, private VPC endpoint cho các tác vụ isolated, và IAM permissions có phạm vi giới hạn.

#### Chiến lược log stream

| Container | Log Group Stream Prefix | File nguồn | Mục đích |
|---|---|---|---|
| RaftDB (production sidecar) | **raftdb** | Infrastructure | Sự kiện Raft consensus, publication snapshot, chuyển đổi health |
| Application (Go/ECS) | **awsplace** | Infrastructure | HTTP request log, WebSocket event, thao tác DynamoDB, thao tác RaftDB client |
| RaftDB (staging members) | **raftdb** | Infrastructure | Sự kiện consensus từng member, giao tiếp peer, thao tác WAL |
| RaftDB qualification tasks | **raftdb-qualification** | Infrastructure | Kết quả qualification test, metric phía client, chẩn đoán lỗi |

Mỗi stream prefix tạo ra một CloudWatch log stream riêng biệt trong log group. Driver **awslogs** được cấu hình trực tiếp trong container definition:

```typescript
// Production sidecar
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'raftdb' }),

// Application container
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'awsplace' }),

// Staging members
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'raftdb' }),

// Qualification tasks
logging: ecs.LogDriver.awsLogs({ streamPrefix: 'raftdb-qualification' }),
```

---

#### 1. IAM Permissions cho Logging

Hàm: **createIamRoles**

ECS task execution role mang các quyền tối thiểu cần thiết để awslogs driver tạo stream và publish event:

```typescript
ecsTaskExecutionRole.addToPolicy(
  new iam.PolicyStatement({
    actions: [
      'logs:CreateLogStream',
      'logs:PutLogEvents',
    ],
    resources: ['*'],
  })
);
```

Quyền **logs:CreateLogGroup** được cố ý **không** cấp — log group được CDK tạo tại thời điểm triển khai, không phải bởi container trong thời gian chạy. Điều này tuân theo nguyên tắc least privilege: một container bị xâm nhập không thể tạo log group mới để che giấu hoạt động của nó.

Lambda execution role sử dụng managed policy của AWS **AWSLambdaBasicExecutionRole**, đã bao gồm quyền ghi CloudWatch Logs cho Lambda function log.

---

#### 2. Private VPC Endpoint cho Tác Vụ Isolated

Hàm: **createRaftDbCluster**

RaftDB staging member chạy trong private isolated subnet không có NAT gateway và không có public IP (khi triển khai dưới dạng cụm 3 node). Để các tác vụ này có thể đẩy log lên CloudWatch, CDK tạo một **CloudWatch Logs VPC interface endpoint** riêng:

```typescript
vpc.addInterfaceEndpoint('RaftDbLogsEndpoint', {
  ...interfaceEndpointOptions,
  service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
});
```

Endpoint này là một phần của bộ ba private interface endpoint (ECR API, ECR Docker, CloudWatch Logs) và một S3 gateway endpoint. Security group của endpoint chỉ chấp nhận TCP 443 từ RaftDB task group — không có lưu lượng nào khác có thể đến dịch vụ CloudWatch Logs qua đường dẫn này.

Bộ VPC endpoint đầy đủ cho staging task isolated được xác thực bởi test **three-member raftdb reaches every AWS service it needs through private endpoints** trong **raftdb.test.cjs**.

---

#### 3. Lưu Trữ và Truy Vấn Log

CloudWatch Logs group được tạo ngầm bởi ECS khi sự kiện log đầu tiên được publish (hoặc được tạo rõ ràng bởi CDK nếu chính sách retention được thiết lập). Khi log đã ở trong CloudWatch:

- **CloudWatch Logs Insights** có thể truy vấn giữa các log group sử dụng stream prefix để lọc theo loại container. Ví dụ: để tìm tất cả lỗi health check RaftDB trên toàn staging cluster:

  ```
  fields @timestamp, @logStream, @message
  | filter @logStream like /raftdb/
  | filter @message like /health/
  | sort @timestamp desc
  | limit 100
  ```

- **Metric filter** có thể được áp dụng lên log group để trích xuất custom metric từ mẫu log — ví dụ: đếm số lượng thông báo "quorum lost" mỗi giờ.
- **Subscription filter** có thể truyền log đến Lambda, Kinesis, hoặc OpenSearch để xử lý và cảnh báo thời gian thực vượt ra ngoài những gì CloudWatch Alarm cung cấp.

---

#### 4. Logging trong CI/CD Pipeline

CI/CD pipeline cũng tạo ra log có cấu trúc bổ sung cho giám sát thời gian chạy:

| Giai đoạn Pipeline | Đầu ra Log | Thời gian lưu |
|---|---|---|
| Go unit test | Tên hàm test và thông báo lỗi trong GitHub Actions log | 90 ngày (mặc định) |
| CDK test suite | Đầu ra Jest với pass/fail cho từng file test | 90 ngày (mặc định) |
| Chuỗi giám sát RaftDB image | Image ID, kết quả scan, đầu ra contract test dưới dạng workflow artifact | 90 ngày (upload artifact rõ ràng) |
| Trivy vulnerability scan | Báo cáo SARIF với chi tiết HIGH/CRITICAL finding | 90 ngày (upload artifact rõ ràng) |

Bằng chứng publication RaftDB (image digest, kết quả contract test, báo cáo scan) được upload dưới dạng workflow artifact với thời gian lưu 90 ngày. Điều này cung cấp một audit trail kết nối container đang chạy với nguồn gốc build, test, và scan của nó.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Mở CloudWatch Logs Insights trong AWS Console.
Chạy một truy vấn lọc theo log group của ứng dụng awsplace.
Chụp giao diện hiển thị trình soạn truy vấn, bộ chọn log stream, và một mẫu kết quả.
Lưu tại: static/images/5.7/logs-insights-query.png

Gợi ý chụp ảnh 2: Mở chi tiết ECS task của một RaftDB member đang chạy.
Cuộn đến tab "Logs" và chụp live log tail hiển thị các mục gần đây với timestamp và cấu hình awslogs driver.
Lưu tại: static/images/5.7/ecs-container-logs.png

Gợi ý chụp ảnh 3: Điều hướng đến VPC Endpoints trong AWS Console.
Lọc theo RaftDB VPC và chụp danh sách hiển thị CloudWatch Logs endpoint cùng với ECR và S3 endpoint.
Lưu tại: static/images/5.7/vpc-endpoints-logging.png
-->
