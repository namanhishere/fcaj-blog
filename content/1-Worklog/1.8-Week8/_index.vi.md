---
title: "Worklog Tuần 8"
date: 2026-08-03
weight: 8
chapter: false
pre: " <b> 1.8. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 8:

* Chuyển production sang `DATA_MODE=raftdb-only`, để ứng dụng chỉ còn đúng một nơi lưu dữ liệu và không có đường dự phòng.
* Làm cho chiến lược triển khai trung thực với ràng buộc bên dưới nó: một tiến trình ghi RaftDB duy nhất sở hữu write-ahead log trên EFS, nên không bao giờ được có hai task cùng chạy.
* Kiểm định image bằng một phép thử vòng tròn thực sự thay vì một health check, và ghi lại đúng tình trạng observability hiện tại thay vì điều mà dashboard gợi ra.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Đọc lại hợp đồng về mode trước khi thay đổi bất cứ thứ gì: DATA_MODE là bộ chọn hành vi lưu trữ lúc chạy, và đổi nó là một lần triển khai task definition, không phải build lại image <br> - **Xác nhận vị trí của raftdb-only trong trình tự:** <br>&emsp; + legacy, rồi dual-write-read-legacy, rồi dual-write-read-raftdb, rồi raftdb-only <br>&emsp; + rollback chỉ được phép khi store cũ vẫn còn đầy đủ và có thẩm quyền <br> - Ghi chú rằng raftdb-only buộc cả hai interface về RaftDB và bỏ qua các giá trị bộ chọn cũ đã lỗi thời <br> - Nhận lấy hệ quả: khi cửa sổ rollback đóng lại, RaftDB là store duy nhất | 03/08/2026 | 03/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html> |
| 3   | - Đặt DATA_MODE, BACKEND và STORAGE về các giá trị raftdb trên container App và trỏ RAFTDB_ADDR tới 127.0.0.1:9100 <br> - Đặt RaftDB làm sidecar bắt buộc trong cùng một task thay vì một service riêng, nên địa chỉ loopback chính là toàn bộ đường mạng <br> - Thêm phụ thuộc container để ECS chỉ khởi động App sau khi RaftDb báo HEALTHY <br> - Suy ra ALLOWED_ORIGINS từ tên miền đã triển khai để một lần triển khai sạch không thể âm thầm quay về chế độ chỉ cùng origin | 04/08/2026 | 04/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking-awsvpc.html> <br> <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html> |
| 4   | - Ghim tỷ lệ triển khai ở minHealthyPercent 0 và maxHealthyPercent 100, và viết lý do ngay cạnh chúng trong mã nguồn <br> - Đặt stopTimeout 120 giây trên container RaftDb để WAL có thời gian flush trước khi task bị dừng <br> - **Thêm deployment circuit breaker kèm rollback bằng property override thô DeploymentConfiguration.DeploymentCircuitBreaker:** <br>&emsp; + thuộc tính L2 cũng sinh ra DeploymentController, thứ sẽ thay thế service đang chạy <br>&emsp; + chấp nhận cảnh báo CDK phát sinh một cách tường minh thay vì tắt nó đi <br> - Giữ desiredCount ở 1 và không thêm autoscaling ở bất cứ đâu | 05/08/2026 | 05/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html> <br> <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html> |
| 5   | - Đọc client raftdb-qualify và ghi lại nó chứng minh và không chứng minh điều gì: hai lệnh con write-read và read, các cờ bắt buộc --key và --value-base64, giới hạn thời gian tổng 30 giây <br> - **Chốt lại hợp đồng mã thoát trong ghi chú của tôi:** <br>&emsp; + 0 kiểm định đạt và evidence JSON đã được ghi <br>&emsp; + 2 lỗi cách dùng hoặc lỗi kiểm tra đầu vào <br>&emsp; + 1 lỗi lúc chạy, bao gồm cả trường hợp giá trị không khớp <br> - Chạy bài kiểm thử hợp đồng kiểm định: ghi, khởi động lại server, rồi đọc lại giá trị <br> - Ghi lại rằng health check của container là một phép thử nông: tệp ready, thư mục dữ liệu ghi được, kết nối TCP, không có bắt tay giao thức | 06/08/2026 | 06/08/2026 | <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html> |
| 6   | - Triển khai với image RaftDB tham chiếu theo digest và theo dõi rollout đạt PRIMARY với một task đang chạy <br> - Xác nhận hình dạng task: hai container, RaftDb trên 9100 và App trên 8980, EFS mount tại /data/raftdb qua access point /raftdb/production/member-1 <br> - Đọc định nghĩa dashboard CloudWatch và ghi lại tình trạng thật: namespace tuỳ chỉnh RaftDb đã được cấp phát nhưng đang ngủ, vì chưa có nơi nào phát số liệu trong mã nguồn <br> - Viết lại rằng production hôm nay không có alarm CloudWatch nào và mọi alarm RaftDB đều nằm trong stack staging | 07/08/2026 | 07/08/2026 | <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html> <br> <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html> |

Câu chú thích giải thích chiến lược triển khai nằm trong CDK, ngay cạnh những giá trị mà nó biện giải, và đó là chỗ nó nên ở:

```typescript
// awsplace/cdk/lib/ecs.ts
desiredCount: 1,
// A single raftdb writer owns the EFS WAL. Stop it before replacement;
// overlapping tasks would open the same durable files concurrently.
minHealthyPercent: 0,
maxHealthyPercent: 100,
```

Circuit breaker được áp lên service đang tồn tại thay vì qua thuộc tính mức cao hơn, với một lý do cũng được ghi lại trong mã nguồn:

```typescript
// awsplace/cdk/lib/ecs.ts
const cfnService = service.node.defaultChild as ecs.CfnService;
cfnService.addPropertyOverride('DeploymentConfiguration.DeploymentCircuitBreaker', {
  Enable: true,
  Rollback: true,
});
```

### Kết quả đạt được tuần 8:

* Production chạy đúng một nơi lưu dữ liệu. Container App mang `DATA_MODE=raftdb-only`, `BACKEND=raftdb`, `STORAGE=raftdb` và `RAFTDB_ADDR=127.0.0.1:9100`, còn RaftDB là sidecar bắt buộc trong cùng một ECS task chứ không phải một service riêng. `awsplace/docs/raftdb/application-modes.md` nói rõ đây là trạng thái cuối sau khi cửa sổ rollback đóng lại, và rằng `raftdb-only` buộc cả hai interface về RaftDB và bỏ qua các giá trị bộ chọn cũ đã lỗi thời. Service chạy một task với hai container đó, `RaftDb` trên 9100 và `App` trên 8980, với image RaftDB tham chiếu theo digest chứ không theo tag.

* Thứ tự khởi động do nền tảng bảo đảm, không phải do một vòng lặp thử lại. `appContainer.addContainerDependencies` với `ContainerDependencyCondition.HEALTHY` nghĩa là ECS không khởi động ứng dụng cho tới khi health check của sidecar đạt, và health check đó chạy mỗi 5 giây với 15 giây khởi động ban đầu và tối đa 10 lần thử lại. Vì nơi lưu dữ liệu duy nhất của ứng dụng được truy cập qua loopback, không có tình huống nào ứng dụng đã lên mà store lại không tới được qua mạng.

* Chiến lược triển khai là một chi phí khả dụng có chủ ý, và được ghi lại đúng như vậy. `minHealthyPercent: 0` cùng `maxHealthyPercent: 100` khiến mọi lần triển khai là dừng-rồi-khởi-động thay vì cuốn dần, vì một tiến trình ghi RaftDB duy nhất sở hữu write-ahead log trên EFS và hai task chồng lấn sẽ mở cùng những tệp bền vững đó. `stopTimeout` là 120 giây để container đang ra đi có thời gian flush trước khi bị dừng. Vì thế canvas offline trong suốt thời gian mỗi lần triển khai. Tôi chọn một lần ngưng ngắn và đoán trước được hơn là khả năng có hai tiến trình ghi trên cùng một WAL.

* Lớp bảo vệ rollback là một property override thô của CloudFormation, và chi tiết đó quan trọng nếu về sau có ai đọc CDK. Đặt thuộc tính L2 `circuitBreaker` cũng sẽ sinh ra `DeploymentController`, thứ mà CloudFormation xem là thay thế service đang chạy; override `DeploymentConfiguration.DeploymentCircuitBreaker` với `Enable` và `Rollback` thì cập nhật service đang sống ngay tại chỗ. Cảnh báo của CDK về việc không dùng thuộc tính L2 được chấp nhận tường minh trong mã nguồn thay vì bị tắt đi, và template sinh ra được kiểm chứng trong `awsplace/cdk/deployment-contract.test.cjs`. `desiredCount` giữ ở 1 và không có construct autoscaling nào trong toàn bộ CDK, nên câu chuyện về năng lực đúng là một task.

* `raftdb-qualify` chứng minh được điều mà health check không thể. Health check xác nhận tệp readiness không rỗng, thư mục dữ liệu là một thư mục ghi được, và kết nối TCP tới `127.0.0.1` trên cổng client thành công; nó không thực hiện bắt tay giao thức và không khẳng định gì về leader hay quorum. `raftdb-qualify` ghi một khoá có tiền tố xác định bằng `write-read`, rồi bài kiểm thử hợp đồng kiểm định dừng server, khởi động lại, và chạy `read` để đòi lại giá trị đúng từng byte. Đó là phép thử độ bền qua một lần khởi động lại, không phải phép thử còn sống. Nó là công cụ cho staging và cho các buổi diễn tập, không phải thành phần của production, và task definition của nó trong CDK cố tình mang một lệnh không hợp lệ để mode phải được cấp lúc chạy.

* Observability là chỗ tôi phải cẩn thận, vì dashboard trông hoàn chỉnh hơn hệ thống thật. `awsplace/cdk/lib/dashboard.ts` định nghĩa chín tên metric dưới namespace tuỳ chỉnh `RaftDb` và bày chúng trên bốn widget, và chính chú thích đầu tệp nói rằng các panel "are dormant until the Raft runtime actually publishes the values". Không có nơi nào phát số liệu: các biến `RAFTDB_METRICS_*` được liệt kê là đã dành trước nhưng chưa hoạt động trong hợp đồng runtime, và không có lệnh gửi metric nào trong mã nguồn RaftDB hay Go. Vậy namespace đó đã được cấp phát nhưng đang ngủ, và tôi không có giá trị đo nào từ nó để báo cáo. Log của container thì thật, mỗi container một tiền tố stream, `raftdb` và `awsplace`.

* Hai khoảng trống nay đã được ghi lại thay vì mặc định bỏ qua. Production không có alarm CloudWatch nào cả: mọi alarm RaftDB, kể cả tuổi snapshot vượt 900 giây và bất kỳ lỗi WAL nào, đều nằm trong stack staging chỉ tồn tại khi `ENABLE_RAFTDB` được đặt, và hai trong số các alarm đó theo dõi đúng cái namespace đang ngủ với `treatMissingData: NOT_BREACHING`, nên chúng sẽ nằm ở trạng thái thiếu dữ liệu chứ không kích hoạt. Lưới an toàn tự động duy nhất của production là deployment circuit breaker. Riêng chuyện khác, `application-modes.md` mô tả hành vi fail-closed lúc khởi động và thứ tự khởi động của ECS, nhưng không nói gì về việc ứng dụng làm gì nếu sidecar mất khả dụng giữa lúc đang chạy ở `raftdb-only`; hành vi đó chưa được ghi lại, và tôi sẽ không mô tả nó như thể đã được thiết kế.
