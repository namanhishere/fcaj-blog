---
title: "CloudWatch Alarms"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 5.8.2. </b> "
---

RaftDB staging stack của awsplace định nghĩa **chín CloudWatch alarm** trải dài trên bốn chiều vận hành: sử dụng tài nguyên, độ bền dữ liệu, độ ổn định triển khai, và tình trạng mạng. Mỗi alarm đều được tạo trong mã CDK và được xác thực bởi bộ Jest test trong **raftdb.test.cjs** — bao gồm assertion về giá trị ngưỡng, toán tử so sánh, và thiết lập quan trọng **TreatMissingData**.

#### Danh sách alarm

| Tên Alarm | Phạm vi | Metric | Ngưỡng | Đánh giá | TreatMissingData |
|---|---|---|---|---|---|
| raftdb1CpuAlarm | Từng member | CPUUtilization (MAX, 1 min) | >= 85% | 3 trên 5 điểm | NOT_BREACHING |
| raftdb2CpuAlarm | Từng member | CPUUtilization (MAX, 1 min) | >= 85% | 3 trên 5 điểm | NOT_BREACHING |
| raftdb3CpuAlarm | Từng member | CPUUtilization (MAX, 1 min) | >= 85% | 3 trên 5 điểm | NOT_BREACHING |
| raftdb1MemoryAlarm | Từng member | MemoryUtilization (MAX, 1 min) | >= 85% | 3 trên 5 điểm | NOT_BREACHING |
| raftdb2MemoryAlarm | Từng member | MemoryUtilization (MAX, 1 min) | >= 85% | 3 trên 5 điểm | NOT_BREACHING |
| raftdb3MemoryAlarm | Từng member | MemoryUtilization (MAX, 1 min) | >= 85% | 3 trên 5 điểm | NOT_BREACHING |
| RaftDbSnapshotAgeAlarm | Toàn cluster | SnapshotAge (MAX, 5 min, math MAX giữa các node) | > 900s (15 phút) | 2 kỳ | NOT_BREACHING |
| RaftDbRestoreFailureAlarm | Toàn cluster | WalErrors (SUM, 5 min, math SUM giữa các node) | > 0 | 1 kỳ | NOT_BREACHING |
| RaftDbTcpLivenessAlarm | Toàn cluster | HealthyHostCount (MIN, 1 min) | < nodeCount | 3 trên 3 điểm | BREACHING |

Các alarm deployment rollback (từng member, CPU < 1% liên tục) bổ sung thêm ba alarm nữa trong triển khai đa node, được đề cập riêng bên dưới.

---

#### 1. Alarm Sử Dụng Tài Nguyên từng Member

Hàm: **createRaftDbMember**

Mỗi RaftDB member nhận alarm CPU và memory riêng. Thiết kế này tránh gộp chung giữa các node để một member bị quá tải được xác định ngay lập tức mà không cần kiểm tra dashboard:

```typescript
const cpuAlarm = new cloudwatch.Alarm(scope, `${nodeName}CpuAlarm`, {
  metric: service.metricCpuUtilization({ period: Duration.minutes(1) }),
  threshold: 85,
  evaluationPeriods: 5,
  datapointsToAlarm: 3,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});

const memoryAlarm = new cloudwatch.Alarm(scope, `${nodeName}MemoryAlarm`, {
  metric: service.metricMemoryUtilization({ period: Duration.minutes(1) }),
  threshold: 85,
  evaluationPeriods: 5,
  datapointsToAlarm: 3,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});
```

Tỷ lệ **3 trên 5** datapoints-to-alarm cung cấp khoảng thời gian đệm 2 phút cho các đợt tăng CPU tạm thời (ví dụ: trong lúc snapshot compaction) trước khi alarm kích hoạt. Điều này khớp với hướng dẫn của capacity runbook: phản ứng ở ngưỡng giám sát 70%, nhưng alarm kích hoạt ở 85% để cho người vận hành thời gian xử lý trước khi bão hoà.

Jest test **per-member CPU and memory alarms exist for all three nodes** xác thực điều này trong **raftdb.test.cjs**:

```javascript
test('per-member CPU and memory alarms exist for all three nodes', () => {
  const template = stagingTemplate();
  const alarms = resourceEntriesByType(template, 'AWS::CloudWatch::Alarm');
  for (let n = 1; n <= 3; n++) {
    const cpuAlarm = alarms.find(([id]) => id.includes(`raftdb${n}CpuAlarm`));
    expect(cpuAlarm).toBeDefined();
    const memoryAlarm = alarms.find(([id]) => id.includes(`raftdb${n}MemoryAlarm`));
    expect(memoryAlarm).toBeDefined();
  }
});
```

---

#### 2. Alarm Độ Bền: Snapshot Age và WAL Errors

File: **Infrastructure**

Hai alarm toàn cluster bảo vệ chống lại các kịch bản mất dữ liệu. Chúng sử dụng CloudWatch **MathExpression** để tổng hợp giữa tất cả member:

#### a) SnapshotAgeAlarm

```typescript
const maxSnapshotAge = new cloudwatch.MathExpression({
  expression: `MAX([${Object.keys(snapshotAgeMetrics).join(', ')}])`,
  usingMetrics: snapshotAgeMetrics,
  period: Duration.minutes(5),
  label: 'Max snapshot age across cluster',
});

new cloudwatch.Alarm(this, 'RaftDbSnapshotAgeAlarm', {
  alarmDescription:
    'Snapshot age exceeds 15 minutes (900 seconds) across the raftdb cluster',
  metric: maxSnapshotAge,
  threshold: 900,
  evaluationPeriods: 2,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});
```

Alarm này sử dụng **MAX** giữa cả ba node, vì vậy nó chỉ kích hoạt khi snapshot của mọi node đều cũ hơn 15 phút. Khoảng thời gian snapshot mặc định là 300 giây (5 phút), do đó 900 giây tương đương với ba chu kỳ snapshot bị bỏ lỡ — một tín hiệu durability rõ ràng. Alarm được xác thực bởi test **snapshot age alarm thresholds on max across nodes, not-breaching on cold start**.

#### b) RestoreFailureAlarm (WAL Errors)

```typescript
const totalWalErrors = new cloudwatch.MathExpression({
  expression: `SUM([${Object.keys(walMetrics).join(', ')}])`,
  usingMetrics: walMetrics,
  period: Duration.minutes(5),
  label: 'Total WAL errors across cluster',
});

new cloudwatch.Alarm(this, 'RaftDbRestoreFailureAlarm', {
  alarmDescription:
    'WAL errors detected in raftdb cluster (potential restore or data corruption)',
  metric: totalWalErrors,
  threshold: 0,
  evaluationPeriods: 1,
  comparisonOperator:
    cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
});
```

Metric WalErrors là bộ đếm tăng dần — bất kỳ giá trị khác 0 nào cũng có nghĩa là WAL corruption hoặc truncation đã xảy ra. Alarm sử dụng aggregation **SUM** và kích hoạt chỉ sau một kỳ đánh giá, khiến nó trở thành alarm phản ứng nhanh nhất trong hệ thống. Được xác thực bởi test **restore failure alarm uses WalErrors with not-breaching on missing data**.

---

#### 3. Alarm Deployment Rollback

File: **Infrastructure**

Đối với triển khai đa node, mỗi member nhận một alarm ổn định triển khai để phát hiện các task không bao giờ khởi động đúng cách sau deploy:

```typescript
for (const member of members) {
  new cloudwatch.Alarm(
    this,
    `${member.nodeName}DeploymentRollbackAlarm`,
    {
      alarmDescription: `Deployment failed to stabilize for ${member.nodeName} (sustained low CPU)`,
      metric: member.service.metricCpuUtilization({
        statistic: cloudwatch.Stats.AVERAGE,
        period: Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 5,
      comparisonOperator:
        cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    },
  );
}
```

Đây là alarm không gian âm (negative-space): CPU liên tục *dưới* 1% trong 5 phút sau deploy có nghĩa là task đang bị kẹt trong vòng lặp crash, không thể bind port, hoặc không bao giờ hoàn tất recovery. Kết hợp với ECS deployment circuit breaker (tự rollback), alarm này cung cấp xác nhận trực quan cho con người rằng đã có sự cố. Test **deployment rollback alarm exists for every member with not-breaching** xác thực điều này.

---

#### 4. Alarm NLB TCP Liveness

File: **Infrastructure**

Cấu trúc liên kết đa node phơi bày RaftDB qua một internal Network Load Balancer. Một alarm liveness giám sát số lượng healthy target của NLB:

```typescript
new cloudwatch.Alarm(this, 'RaftDbTcpLivenessAlarm', {
  alarmDescription:
    'TCP liveness only: the internal NLB has no healthy RaftDB target',
  metric: healthyTargets,
  threshold: nodeCount,
  evaluationPeriods: 3,
  datapointsToAlarm: 3,
  comparisonOperator:
    cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
  treatMissingData: cloudwatch.TreatMissingData.BREACHING,
});
```

Đây là **alarm duy nhất** sử dụng **BREACHING** cho dữ liệu thiếu. Lý do: nếu bản thân NLB metric không tồn tại, load balancer hoặc đường dẫn logging của nó đã bị lỗi, bản thân điều này đã là một tình trạng cần hành động. Test **staging alarms when provider TCP liveness has no healthy target** xác thực sự tồn tại và cấu hình của alarm này.

---

#### Triết lý TreatMissingData

Lựa chọn giữa **NOT_BREACHING** và **BREACHING** là có chủ đích cho từng alarm:

| Thiết lập | Dùng cho | Lý do |
|---|---|---|
| NOT_BREACHING | CPU, memory, snapshot age, WAL errors, deployment rollback | Stack khởi động lạnh hoặc vừa deploy thiếu lịch sử metric; cảnh báo sẽ tạo ra dương tính giả |
| BREACHING | NLB TCP liveness | Nếu luồng NLB metric ngừng hoàn toàn, đường dẫn load-balancing đã hỏng — đây là tình trạng cần hành động |

Điều này ngăn chặn mô hình "mệt mỏi vì alarm" (alarm fatigue) — nơi người vận hành học cách bỏ qua alarm vì chúng kích hoạt trong mỗi lần triển khai.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Mở CloudWatch Alarms trong AWS Console.
Lọc theo alarm của RaftDB staging stack và chụp danh sách hiển thị tất cả 9+ alarm với trạng thái hiện tại (OK/ALARM/INSUFFICIENT_DATA).
Lưu tại: static/images/5.7/cloudwatch-alarms-list.png

Gợi ý chụp ảnh 2: Click vào RaftDbSnapshotAgeAlarm.
Chụp giao diện chi tiết alarm hiển thị ngưỡng (900s), math expression, và đồ thị metric.
Lưu tại: static/images/5.7/snapshot-age-alarm-detail.png
-->
