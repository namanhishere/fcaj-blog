---
title: "Health Check Container & Ứng dụng"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 5.8.3. </b> "
---

Dự án awsplace sử dụng health check ở ba tầng — ECS container health, thứ tự phụ thuộc container, và ALB target group health — để đảm bảo chỉ những dịch vụ được khởi tạo đúng cách mới nhận lưu lượng. Các health check này được định nghĩa trong mã hạ tầng, và lệnh cùng tham số chính xác của chúng được thực thi bởi các Jest contract test.

#### Các tầng health check

| Tầng | Cơ chế | Định nghĩa tại | Hành vi khi thất bại |
|---|---|---|---|
| RaftDB container | Lệnh HEALTHCHECK (**raftdb-healthcheck**) | Infrastructure | ECS khởi động lại container sau 10 lần thất bại liên tiếp |
| Application container | DependsOn RaftDB container với điều kiện **HEALTHY** | Infrastructure | App container không khởi động cho đến khi RaftDB vượt qua health check |
| ALB target group | HTTP health probe trên đường dẫn **/health** | Infrastructure | ALB rút target khỏi phục vụ; ECS deployment circuit breaker có thể rollback |

---

#### 1. Health Check RaftDB Container

Hàm: **createRaftDbMember**

Mỗi RaftDB container (cả production sidecar và staging member) đều chạy cùng một lệnh health:

```typescript
healthCheck: {
  command: ['CMD', '/usr/local/bin/raftdb-healthcheck'],
  interval: Duration.seconds(5),
  timeout: Duration.seconds(3),
  retries: 10,
  startPeriod: Duration.seconds(15),
},
```

Health check này được điều chỉnh bởi **runtime contract** định nghĩa trong **docs/raftdb/runtime-contract.md**. Hợp đồng quy định:

| Thuộc tính | Giá trị | Lý do |
|---|---|---|
| **Interval** | 5 giây | Phát hiện nhanh: một node lỗi được phát hiện trong vòng 50 giây (10 lần thử × 5s) |
| **Timeout** | 3 giây | Health check nhẹ — chỉ xác thực readiness marker, tạo file probe, mở port, rồi xoá probe |
| **Retries** | 10 | Cho phép tranh chấp tài nguyên tạm thời (vd: cạn burst credit EFS) tự giải quyết mà không cần khởi động lại |
| **Start period** | 15 giây | Recovery (khôi phục snapshot + phát lại WAL) có thể mất vài giây; thời gian đệm ngăn thất bại sớm |

Binary **raftdb-healthcheck** xác thực ba điều kiện trước khi báo cáo thành công:

1. **Readiness marker tồn tại** — Server chỉ tạo file không rỗng tại **/tmp/raftdb-ready** sau khi recovery local hoặc S3 hoàn tất thành công. Nếu marker vắng mặt, recovery vẫn đang tiến hành hoặc đã thất bại.
2. **Durable mount có thể ghi** — Health check tạo, ghi, và xoá file probe tạm thời dưới **RAFTDB_DATA_DIR** để xác nhận EFS access point đã được mount và có thể ghi.
3. **Client port đang mở** — Health check mở kết nối TCP tới client port local (**9100**) để xác nhận listener đang chấp nhận kết nối.

Trước khi recovery bắt đầu, server xoá mọi readiness marker cũ từ lần chạy trước. Stale process marker, durable mount chỉ đọc hoặc không khả dụng, recovery chưa hoàn tất, hoặc listener đã đóng — tất cả đều dẫn đến health check thất bại, và ECS coi container đó là không healthy.

Jest test xác thực lệnh health check chính xác trong **raftdb.test.cjs**:

```javascript
expect(container.HealthCheck.Command).toEqual([
  'CMD',
  '/usr/local/bin/raftdb-healthcheck',
]);
```

---

#### 2. Thứ Tự Phụ Thuộc Container

Hàm: **createEcs**

Application container phụ thuộc vào RaftDB sidecar đạt trạng thái healthy trước khi nó khởi động:

```typescript
appContainer.addContainerDependencies({
  container: raftDbContainer,
  condition: ecs.ContainerDependencyCondition.HEALTHY,
});
```

Sự phụ thuộc này được xác thực bởi test **application runs exclusively against its healthy raftdb sidecar** trong **raftdb.test.cjs**:

```javascript
expect(app.DependsOn).toContainEqual({ ContainerName: 'RaftDb', Condition: 'HEALTHY' });
```

Nếu không có đảm bảo thứ tự này, application container có thể khởi động trước khi RaftDB sidecar hoàn tất recovery, khiến mọi request ban đầu thất bại. Điều kiện **HEALTHY** là điều kiện mạnh nhất hiện có — nó yêu cầu cả ba xác thực health check (readiness marker, writable mount, open port) đều vượt qua trước khi sự phụ thuộc được thoả mãn.

Đối với RaftDB staging member, không có sự phụ thuộc tương đương vì mỗi member là một ECS service độc lập. NLB health check cung cấp chức năng gating tương đương.

---

#### 3. ALB Target Group Health Check

Hàm: **createEcs**

Application Load Balancer production xác thực tình trạng ứng dụng qua một HTTP endpoint:

```typescript
healthCheck: {
  path: '/health',
  interval: Duration.seconds(30),
  timeout: Duration.seconds(5),
  healthyThresholdCount: 2,
},
```

Đây là một HTTP health probe tiêu chuẩn ở tầng ứng dụng:

| Thuộc tính | Giá trị | Lý do |
|---|---|---|
| **Path** | /health | Một health endpoint chuyên dụng trả về 200 OK khi ứng dụng sẵn sàng |
| **Interval** | 30 giây | Tình trạng tầng ứng dụng thay đổi chậm hơn tầng container; 30s tránh lưu lượng probe không cần thiết |
| **Timeout** | 5 giây | Handler /health nhẹ; 5s là hào phóng cho một lần health check dưới tải |
| **Healthy threshold** | 2 | Yêu cầu hai lần thành công liên tiếp trước khi target được đưa trở lại phục vụ |

ALB health check phối hợp với **DeploymentCircuitBreaker** để cung cấp phòng thủ theo chiều sâu trong quá trình triển khai:

```typescript
cfnService.addPropertyOverride('DeploymentConfiguration.DeploymentCircuitBreaker', {
  Enable: true,
  Rollback: true,
});
```

Nếu một task mới thất bại ALB health check, circuit breaker sẽ tự động rollback đợt triển khai. Alarm deployment rollback (đã đề cập trong 5.7.2) cung cấp xác nhận trực quan rằng điều này đã xảy ra.

---

#### 4. Hợp Đồng Readiness Marker

Readiness marker tại **/tmp/raftdb-ready** là chốt khoá của hệ thống health check. Vòng đời marker được định nghĩa trong runtime contract:

1. **Trước recovery**: Server xoá mọi marker cũ từ tiến trình trước.
2. **Sau khi recovery thành công**: Server tạo marker không rỗng một cách nguyên tử (atomically), *sau đó* mở client port. Thứ tự này rất quan trọng — một port chấp nhận kết nối trước khi recovery hoàn tất sẽ phục vụ dữ liệu không nhất quán.
3. **Trong khi shutdown**: Server xoá marker khi bắt đầu shutdown, khiến health check thất bại và ECS rút cạn kết nối trước khi tiến trình thoát.

Hợp đồng này có nghĩa là health check cung cấp một tín hiệu trung thực: nếu marker tồn tại, server đã hoàn tất recovery, có durable store ghi được, và sẵn sàng phục vụ client request.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Mở ECS console, điều hướng đến một RaftDB task, và xem tab "Health" hoặc chi tiết container hiển thị cấu hình health check và trạng thái cuối cùng.
Lưu tại: static/images/5.7/ecs-health-check.png

Gợi ý chụp ảnh 2: Mở EC2 Target Groups console, chọn ECS target group, và chụp tab "Health checks" hiển thị đường dẫn /health, interval, timeout, và thiết lập threshold.
Lưu tại: static/images/5.7/alb-target-health.png
-->
