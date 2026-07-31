---
title: "CloudWatch Dashboards"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.8.1. </b> "
---

Mã nguồn CDK của awsplace tạo ra hai CloudWatch dashboard — một **RaftDB staging dashboard** trong RaftDbStagingStack và một **production RaftDB sidecar dashboard** được tạo thông qua các hàm hạ tầng dùng chung. Tất cả widget dashboard đều được định nghĩa trong file **Infrastructure** và **Infrastructure** bên trong thư mục **cdk/lib/**. Bộ Jest test xác thực rằng mọi metric đã lên kế hoạch đều xuất hiện trong dashboard body.

#### Tổng quan dashboard

| Dashboard | Phạm vi | File nguồn | Widget chính |
|---|---|---|---|
| RaftDbDashboard | Staging cluster (3-node Raft) | createRaftDbCluster | EFS I/O limit, burst credits, ECS utilization từng member, NLB target health, panel Raft consensus |
| Production Raft sidecar | Application stack (1-node sidecar) | createRaftDbApplicationStorage | Tín hiệu EFS provider |

Tất cả dashboard đều được xuất dưới dạng CloudFormation output (**RaftDbDashboardName**), cho phép khám phá tên dashboard từ stack output mà không cần mở AWS Console.

---

#### 1. Widget tín hiệu EFS Provider

Hàm: **createRaftDbCluster**

Mỗi dashboard RaftDB cluster bắt đầu với một hàng EFS health hiển thị:

| Metric | Namespace | Statistic | Period | Ý nghĩa |
|---|---|---|---|---|
| PercentIOLimit | AWS/EFS | MAXIMUM | 1 min | Mức độ gần đạt giới hạn I/O throughput của file system |
| ClientConnections | AWS/EFS | AVERAGE | 1 min | Số lượng NFS client connection từ ECS task |
| BurstCreditBalance | AWS/EFS | MINIMUM | 5 min | Burst credit còn lại trước khi bị giới hạn throughput |

```typescript
dashboard.addWidgets(
  new cloudwatch.GraphWidget({
    title: 'RaftDB EFS provider signals',
    left: [
      new cloudwatch.Metric({
        namespace: 'AWS/EFS',
        metricName: 'PercentIOLimit',
        dimensionsMap: efsDimensions,
        statistic: cloudwatch.Stats.MAXIMUM,
        period: Duration.minutes(1),
        label: 'I/O limit %',
      }),
      new cloudwatch.Metric({
        namespace: 'AWS/EFS',
        metricName: 'ClientConnections',
        dimensionsMap: efsDimensions,
        statistic: cloudwatch.Stats.AVERAGE,
        period: Duration.minutes(1),
        label: 'Client connections',
      }),
    ],
    right: [
      new cloudwatch.Metric({
        namespace: 'AWS/EFS',
        metricName: 'BurstCreditBalance',
        dimensionsMap: efsDimensions,
        statistic: cloudwatch.Stats.MINIMUM,
        period: Duration.minutes(5),
        label: 'Burst credits',
      }),
    ],
    leftYAxis: { min: 0 },
    rightYAxis: { min: 0 },
  }),
);
```

Thiết kế trục Y kép tách biệt metric tốc độ (bên trái) khỏi credit tích luỹ (bên phải), ngăn thang đo burst-credit làm phẳng đường I/O limit.

---

#### 2. Widget Custom Metric Raft Consensus

Hàm: **addRaftConsensusWidgets**

RaftDB runtime phát ra custom CloudWatch metric dưới namespace **RaftDb** với dimension **Cluster** và **NodeId**. Các metric này được định nghĩa trong planned emission contract và được hiển thị trên dashboard qua bốn widget chuyên dụng:

| Tiêu đề Widget | Metric hiển thị | Chiều cao | Câu hỏi vận hành |
|---|---|---|---|
| Raft consensus: leader, term, quorum | LeaderId, Term, QuorumStatus (từng node, MAX, 1 min) | 6 | Ai là leader? Quorum có được duy trì không? |
| Raft replication lag | ReplicationLag (từng node, MAX, 1 min) | 5 | Có follower nào đang tụt lại sau leader không? |
| Raft commit index vs applied index | CommitIndex, AppliedIndex (từng node, MAX, 1 min) | 5 | State machine có theo kịp log không? |
| Raft durability: snapshot age, WAL errors, membership | SnapshotAge (MAX, 5 min), WalErrors (SUM, 5 min), MembershipChanges (MAX, 5 min) | 5 | Lưu trữ bền vững có khoẻ không? Snapshot có gần đây không? |

Hợp đồng metric được định nghĩa dưới dạng typed interface trong mã hạ tầng:

```typescript
interface RaftMetricProps {
  readonly metricName: string;
  readonly label: string;
  readonly statistic: string;
  readonly period: Duration;
  readonly unit?: cloudwatch.Unit;
}
```

Mỗi metric được khởi tạo cho từng node, tạo ra một góc nhìn đa node toàn diện. Danh sách đầy đủ custom metric bao gồm:

- **LeaderId** (Count) — ID node leader hiện tại; 0 nghĩa là không phải leader
- **Term** (Count) — Raft term đơn điệu tăng
- **ReplicationLag** (Count) — Số log entry tụt lại sau leader
- **CommitIndex** (Count) — Log entry cao nhất đã được commit
- **AppliedIndex** (Count) — Log entry cao nhất đã được áp dụng vào state machine
- **QuorumStatus** (Count) — 1 = có quorum, 0 = mất quorum
- **SnapshotAge** (Seconds) — Số giây kể từ snapshot bền vững gần nhất
- **WalErrors** (Count) — Số lỗi WAL corruption hoặc truncation
- **MembershipChanges** (Count) — Số lần thay đổi membership đã commit

Tất cả chín metric đều được xác thực bởi Jest test **staging dashboard includes RaftDb custom-metric panels for all 3 nodes** trong **raftdb.test.cjs**.

---

#### 3. Widget ECS Utilization từng Member

Hàm: **createRaftDbMember**

Mỗi RaftDB member nhận một widget ECS utilization riêng hiển thị mức sử dụng CPU và memory:

```typescript
dashboard.addWidgets(
  new cloudwatch.GraphWidget({
    title: `${nodeName} ECS utilization`,
    left: [
      service.metricCpuUtilization({
        period: Duration.minutes(1),
        statistic: cloudwatch.Stats.AVERAGE,
        label: 'CPU %',
      }),
      service.metricMemoryUtilization({
        period: Duration.minutes(1),
        statistic: cloudwatch.Stats.AVERAGE,
        label: 'Memory %',
      }),
    ],
    leftYAxis: { min: 0, max: 100 },
  }),
);
```

Trục Y được giới hạn 0–100% để các thay đổi utilization có ý nghĩa trực quan — một mức tăng 5% CPU trên trục auto-scale mặc định 0–3% sẽ không thể nhìn thấy. Các widget này nằm cùng vị trí với CPU và memory alarm kích hoạt ở mức 85%.

---

#### 4. NLB Target TCP Liveness

Đối với triển khai đa node (3 member), một widget bổ sung theo dõi số lượng healthy và unhealthy target của internal Network Load Balancer:

```typescript
dashboard.addWidgets(
  new cloudwatch.GraphWidget({
    title: 'RaftDB target TCP liveness',
    left: [
      healthyTargets.with({ label: 'Healthy targets' }),
      unhealthyTargets.with({ label: 'Unhealthy targets' }),
    ],
    leftYAxis: { min: 0 },
  }),
);
```

Widget này được ghép cặp với **RaftDbTcpLivenessAlarm** kích hoạt khi healthy target giảm xuống dưới số lượng node mong đợi.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Mở CloudWatch Dashboards console trên AWS.
Điều hướng đến RaftDB dashboard và chụp toàn bộ giao diện hiển thị tất cả widget:
EFS signals, Raft consensus panels, ECS utilization từng member, và NLB liveness.
Lưu tại: static/images/5.7/raftdb-dashboard.png

Gợi ý chụp ảnh 2: Chọn một widget Raft consensus (ví dụ: "Raft consensus: leader, term, quorum").
Phóng to vào khoảng thời gian xảy ra chuyển đổi leadership để hiển thị các chuyển tiếp metric.
Lưu tại: static/images/5.7/raft-consensus-widget.png
-->
