---
title : "Cơ sở hạ tầng RaftDB & Route 53"
date : 2024-01-01
weight : 8
chapter : false
pre : " <b> 5.3.8 </b> "
---

Phần này bao gồm lớp DNS/TLS (**Route 53 + ACM**) và **cơ sở hạ tầng staging RaftDB** (tồn tại dưới dạng một stack CloudFormation riêng biệt tùy chọn cho đánh giá và diễn tập khôi phục).

---

#### Route 53 & ACM

Module Route 53 (**createRoute53AndCertificates**) tạo nền tảng DNS và TLS cho kiến trúc tên miền phân tách.

```typescript
export function createRoute53AndCertificates(
  scope: Construct,
  input: Route53AndCertInput
): Route53AndCertOutput {
  const { domainName, hostedZoneId } = input;

  // Nhập hosted zone hiện có
  const hostedZone = route53.HostedZone.fromHostedZoneAttributes(
    scope, 'HostedZone',
    { hostedZoneId, zoneName: domainName }
  );

  // Tạo chứng chỉ wildcard bao phủ tất cả subdomain
  const wildcardCert = new acm.Certificate(scope, 'WildcardCertificate', {
    domainName: `*.${domainName}`,
    validation: acm.CertificateValidation.fromDns(hostedZone),
  });

  return { hostedZone, wildcardCert };
}
```

**Đặc điểm chính:**

| Thành phần | Giá trị | Mục đích |
|------------|--------|----------|
| Hosted Zone | Nhập theo ID + tên | Phải tồn tại trước khi triển khai (tạo thủ công hoặc bởi stack riêng) |
| Chứng chỉ | Wildcard *.domainName | Bao phủ api.domain.com VÀ ws.domain.com |
| Xác thực | DNS (tự động) | CDK tạo bản ghi xác thực DNS trong hosted zone |

**Chứng chỉ wildcard được sử dụng bởi hai module:**

| Module | Tên miền | Giao thức | Cổng |
|--------|----------|-----------|------|
| API Gateway | api.domain.com | HTTPS | 443 |
| ECS ALB | ws.domain.com | HTTPS | 443 |

**TLS riêng cho Amplify:** Tên miền gốc (domain.com) có TLS được Amplify Hosting tự quản lý — Amplify cung cấp và quản lý chứng chỉ ACM riêng. Không có chứng chỉ do CDK quản lý nào được sử dụng cho tên miền gốc.

---

#### RaftDB Staging Stack

**RaftDbStagingStack** là một **stack CloudFormation thứ hai tùy chọn** được tạo khi **ENABLE_RAFTDB=true**. Nó cung cấp một môi trường dùng một lần, cô lập để đánh giá RaftDB, diễn tập khôi phục và thực hành thay thế thành viên. Nó KHÔNG được sử dụng trong production — RaftDB production chạy như một sidecar trong ECS task chính.

**Tạo stack (có điều kiện trong điểm vào):**
```typescript
if (process.env.ENABLE_RAFTDB === 'true') {
  const stagingStack = new RaftDbStagingStack(app, 'RaftDbStagingStack', {
    env,
    imageDigest: process.env.RAFTDB_IMAGE_DIGEST,
    dataGeneration: process.env.RAFTDB_DATA_GENERATION,
    restoreFromS3: parseRestoreFromS3(process.env.RAFTDB_RESTORE_FROM_S3),
    nodeCount: parseNodeCount(process.env.RAFTDB_NODE_COUNT),
  });
  stagingStack.addDependency(mainStack,
    'RaftDB staging nhập ECR repository chung');
}
```

**Tham số cấu hình stack:**

| Tham số | Mặc định | Giá trị hợp lệ | Mục đích |
|---------|---------|----------------|----------|
| **imageDigest** | — (bắt buộc) | sha256:\<64 ký tự hex\> | Image RaftDB bất biến để đánh giá |
| **dataGeneration** | staging-1 | Slug chữ thường, 1-63 ký tự | Thế hệ đường dẫn EFS (/raftdb/\<gen\>/member-N); thay đổi để có WAL mới |
| **restoreFromS3** | false | true/false | Có khôi phục từ snapshot S3 không; yêu cầu dataGeneration bắt đầu bằng restore- |
| **nodeCount** | 1 | 1 hoặc 3 | Đơn node (đánh giá) hoặc 3-node (đánh giá cụm Raft đầy đủ) |

**Cấu hình VPC phụ thuộc vào số lượng node:**

| Số lượng Node | Kiểu Subnet | Số AZ | Truy cập |
|--------------|-------------|-------|----------|
| 1 (đơn node) | PUBLIC | 1 AZ | TCP 9100 trực tiếp từ mọi nơi (đánh giá staging) |
| 3 (ba node) | PRIVATE_ISOLATED | 3 AZ | Chỉ nội bộ (Raft peer-to-peer trên cổng 9101) |

![Sơ đồ Kiến trúc Diễn tập RaftDB](/images/5-Workshop/5.3-CDK-Project-Structure/raftdb-staging.png)

**Tài nguyên staging stack (cụm chung):**

| Tài nguyên | Loại | Mục đích |
|------------|------|----------|
| ECS Cluster | Fargate | Chạy các tác vụ staging RaftDB |
| NLB | Network Load Balancer (chỉ đa node) | Cân bằng tải TCP trên cổng 9100 |
| Cloud Map Namespace | Service discovery | Khám phá peer RaftDB |
| EFS FileSystem | NFS mã hóa | WAL bền vững cho mỗi thành viên |
| EFS Access Points | Thực thi POSIX | UID/GID 10001:10001 cho mỗi thành viên |
| S3 Snapshot Bucket | Có phiên bản | Snapshot RaftDB định kỳ |
| CloudWatch Dashboard | Số liệu tùy chỉnh | Giám sát Raft consensus |
| Security Groups | Cho mỗi thành viên + client | Peer-to-peer TCP 9101 + client TCP 9100 |

**Giám sát:** Staging stack bao gồm CloudWatch alarms và dashboard:

| Cảnh báo | Số liệu | Ngưỡng |
|----------|--------|--------|
| Snapshot Age | MAX(SnapshotAge) trên cụm | > 15 phút (900s) |
| WAL Errors | SUM(WalErrors) trên cụm | > 0 |
| Deployment Stability | CPU utilization mỗi service | < 1% trong 5 chu kỳ |
| NLB Liveness | Số lượng mục tiêu khỏe mạnh | < số node trong 3 chu kỳ |

**Quy trình thay thế thành viên** (được ghi trong staging stack):

```
1. XÓA thành viên cũ khỏi cấu hình Raft (thay đổi thành viên đã commit)
2. DỪNG ECS task cũ (desiredCount=0)
3. CUNG CẤP EFS access point mới (tăng dataGeneration, ví dụ: staging-2)
4. KHỞI ĐỘNG task thay thế (desiredCount=1) — WAL trống, catalog sạch
5. CÀI ĐẶT snapshot + WAL tail từ peer
6. THÊM thành viên trở lại cụm Raft
7. XÁC MINH quorum + chỉ số đã áp dụng hội tụ
```

**Quy tắc an toàn quan trọng:**
- **Không bao giờ xóa hai voter cùng lúc** — có thể mất quorum
- **Không bao giờ tái sử dụng member ID** trong khi task khác với ID đó có thể chạy
- **Thay đổi quorum khẩn cấp yêu cầu phê duyệt bằng văn bản + backup đã xác minh**

---

#### RaftDB Cluster Factory

Module này cung cấp các hàm factory có thể tái sử dụng để tạo cụm RaftDB:

- **createRaftDbCluster()** — Tạo cơ sở hạ tầng chung: ECS cluster, NLB, Cloud Map namespace, EFS, S3 snapshot bucket, CloudWatch dashboard
- **createRaftDbMember()** — Tạo tài nguyên cho mỗi thành viên: EFS access point, ECS Fargate service + task definition

Các hàm này được sử dụng bởi cả staging stack và có thể được kết hợp cho triển khai production đa node.

---

#### CloudWatch Dashboard

Module dashboard (**addRaftConsensusWidgets**) thêm số liệu cụ thể về Raft vào CloudWatch dashboard:

- **Trạng thái Raft** (chuyển đổi leader/follower/candidate)
- **Sao chép log** (applied index, commit index, last log index)
- **Số liệu snapshot** (tuổi snapshot, kích thước snapshot, số lượng snapshot)
- **Số liệu mạng** (RUDP retransmissions, TCP connection count)
- **Số liệu WAL** (WAL errors, WAL bytes written, segment count)

Các số liệu tùy chỉnh này được phát ra bởi tiến trình RaftDB C++ và cung cấp khả năng hiển thị sâu vào sức khỏe Raft consensus.

---

#### Tổng quan: Cơ sở hạ tầng Hoàn chỉnh

```
┌────────────────────────────────────────────────────────────────────┐
│  Route 53 Hosted Zone (domain.com)                                 │
│  ├── domain.com          → Amplify (TLS được quản lý)              │
│  ├── api.domain.com      → API Gateway (wildcard cert)             │
│  └── ws.domain.com       → ALB (wildcard cert)                     │
│                                                                    │
│  ACM Wildcard Certificate (*.domain.com)                           │
│  ├── api.domain.com (API Gateway custom domain)                    │
│  └── ws.domain.com  (ALB HTTPS listener)                           │
│                                                                    │
│  VPC (2 AZ, chỉ public subnets, không NAT Gateway)                 │
│  ├── ALB (internet-facing, HTTPS 443 → ECS:8980)                   │
│  │   └── Kiểm tra sức khỏe: GET /health (30s)                      │
│  ├── ECS Fargate (1 task: 1024 CPU / 2048 MiB)                     │
│  │   ├── RaftDB sidecar (:9100, non-root 10001)                    │
│  │   │   └── Gắn kết EFS: /data/raftdb (mã hóa)                    │
│  │   └── Go App (:8980)                                            │
│  │       └── depends_on: RaftDB HEALTHY                            │
│  └── Security Groups:                                              │
│      ├── ALB SG: 0.0.0.0/0 → :80, :443                             │
│      └── ECS SG: ALB SG → :8980                                    │
│                                                                    │
│  DynamoDB (4 bảng, on-demand billing)                              │
│  S3 Buckets (canvas + exports + RaftDB snapshots)                  │
│  ECR Repository (awsplace-ecs, giữ 10, raftdb-* bất biến)          │
│  Lambda (Node.js 24, 512 MB, 30s timeout, KHÔNG VPC)               │
│  └── API Gateway HTTP API v2 ($default route → Lambda)             │
│  Amplify Hosting (triển khai zip thủ công, SPA rewrite)            │
│  Secrets Manager: awsplace/app-secrets                             │
│  IAM Roles (3 roles, giới hạn đặc quyền tối thiểu)                 │
└────────────────────────────────────────────────────────────────────┘
```
