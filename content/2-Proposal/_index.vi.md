---
title: "Proposal"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 2. </b> "
includeInReport: false
---
## awsplace là gì

awsplace là một pixel canvas cộng tác thời gian thực. Người dùng đã đăng nhập có thể đặt một pixel (chọn từ 16 màu có sẵn) lên một lưới dùng chung, và pixel đó sẽ hiện trên tất cả client đang kết nối ngay lập tức qua WebSocket. Lưới không cố định — nó có thể mở rộng sang trái, phải, lên hoặc xuống, either theo lệnh admin hoặc tự động vào một ngày đã hẹn trước, và các hình vẽ hiện có vẫn nguyên vẹn sau khi mở rộng.

Việc đặt pixel có giới hạn. Khách vãng lai chỉ được xem canvas; muốn đặt phải đăng nhập Discord, và mỗi user có cooldown để hạn chế tần suất. Admin (xác định bằng danh sách Discord user-ID cho phép) có một dashboard riêng với thống kê thời gian thực và preview canvas, mở rộng bảng thủ công, quản lý milestone, xóa vùng chữ nhật, ban user và IP, điều chỉnh cooldown tại chỗ, và feed hoạt động gần đây.

## Dành cho ai

Ba nhóm người dùng, mỗi nhóm có nhu cầu riêng.

**Người tham gia** là người vẽ. Họ cần canvas load nhanh trong một lần, thấy pixel của người khác mà không cần refresh, và được báo rõ ràng khi đặt bị từ chối cùng lý do. Giao thức WebSocket phục vụ đúng chỗ đó: `INIT_DATA` mang toàn bộ lưới, bảng màu, kích thước và cooldown khi kết nối, `PIXEL_UPDATE` mang một pixel đã đổi, `BOARD_RESIZE` mang kích thước mới, và `ERROR` mang lý do từ chối.

**Admin** điều hành sự kiện. Họ cần mở rộng bảng, hẹn lịch mở rộng sau, xử lý vi phạm và điều chỉnh cooldown khi sự kiện đang diễn ra mà không cần redeploy. Mười route admin phục vụ mục đích đó, và mọi mutation đều kiểm tra same-origin header trước khi tra cứu danh sách admin cho phép.

**Vận hành** — trong kỳ thực tập này nghĩa là mình — cần redeploy một service có trạng thái mà không làm hỏng nó, biết chính xác byte nào đang chạy trên production, và tái tạo toàn bộ môi trường từ source. Yêu cầu này đã định hình phần lớn quyết định hạ tầng trong mục 2.4.

## Cái gì đã giao

Hai sản phẩm, và cả hai đều cần để dự án được tính là hoàn thành.

Thứ nhất là **trang public đang chạy** tại `place.namanhishere.com`. Frontend được host bởi AWS Amplify Hosting; endpoint WebSocket là `ws.place.namanhishere.com` trước một Application Load Balancer public; surface REST cho auth và admin là `api.place.namanhishere.com` trên API Gateway HTTP API. Cả ba hostname đều resolve trong Route 53 hosted zone.

Thứ hai là **hạ tầng có thể tái tạo dưới dạng code**. Toàn bộ môi trường là một CloudFormation stack, `AwsplaceStack`, được tổng hợp từ TypeScript bởi AWS CDK. Không có gì trên production được tạo thủ công trong console.

![awsplace deployment architecture](/images/archtechture.png)

## Phạm vi dự án

**Trong phạm vi**

- Pixel canvas cộng tác thời gian thực qua WebSocket, nơi người dùng đã đăng nhập đặt một trong 16 màu mỗi cooldown interval lên lưới dùng chung
- Luồng đăng nhập Discord OAuth2: redirect, đổi code, cookie phiên HS256 JWT, endpoint nhận diện `/api/me`
- Áp dụng cooldown theo user, admin có thể điều chỉnh tại thời gian chạy mà không cần redeploy
- Mở rộng bảng động theo bốn hướng, admin kích hoạt thủ công hoặc milestone đã hẹn tự động触发, hình vẽ hiện có được giữ nguyên qua dịch tọa độ offset
- Dashboard admin tại `/admin.html` với thống kê thời gian thực, preview canvas, mở rộng thủ công, CRUD milestone, xóa vùng chữ nhật, ban user và IP, điều chỉnh cooldown, và feed hoạt động gần đây
- Lưu trữ canvas dựa trên RaftDB, một engine lưu trữ C++23 tự viết dùng Raft-consensus với WAL phân đoạn và snapshot S3 định kỳ
- Hạ tầng dạng code: một CDK stack (`AwsplaceStack`) bằng TypeScript tạo ra mọi tài nguyên AWS; không có gì được tạo thủ công trong console
- Pipeline CI/CD với test tự động (unit, integration, contract); quét ảnh Trivy; xác thực OIDC khi publish ECR; và deploy frontend Amplify

**Ngoài phạm vi**

- Deploy đa vùng hoặc nhân bản cross-region
- Ứng dụng native mobile hoặc desktop
- Nhà cung cấp xác thực ngoài Discord
- Chat, nhắn tin, hoặc tính năng mạng xã hội
- Hoàn tác hoặc lịch sử chỉnh sửa theo user cho từng pixel
- Xuất canvas ra nền tảng ngoài hoặc dịch vụ lưu trữ ảnh

## Yêu cầu chức năng

| ID | Yêu cầu |
|----|---------|
| FR-01 | Khách vãng lai có thể xem canvas và nhận broadcast pixel thời gian thực mà không cần đăng nhập |
| FR-02 | Đặt pixel yêu cầu xác thực qua Discord OAuth2; lượt đặt không xác thực sẽ nhận thông báo `AUTH_REQUIRED` qua WebSocket |
| FR-03 | Người dùng đã đăng nhập chọn từ bảng 16 màu cố định và đặt một pixel mỗi cooldown interval; server kiểm tra tọa độ và chỉ số màu trước khi ghi |
| FR-04 | Mỗi lượt đặt được chấp nhận sẽ broadcast dưới dạng tin nhắn `PIXEL_UPDATE` đến tất cả client đang kết nối |
| FR-05 | Bảng mở rộng trái, phải, lên hoặc xuống mà không hỏng hình vẽ hiện có; mở rộng trái hoặc lên dịch tọa độ pixel qua global offset |
| FR-06 | Admin hẹn lịch mở rộng (milestone) với thời gian kích hoạt, hướng, số pixel, và nhãn tùy chọn; server tự động thực hiện |
| FR-07 | Admin có thể mở rộng bảng theo yêu cầu từ dashboard |
| FR-08 | Admin có thể xóa một vùng chữ nhật trên canvas về trắng bằng cách chỉ định tọa độ góc (superpaint) |
| FR-09 | Admin có thể ban hoặc unban user theo Discord ID và theo IP; lệnh ban được kiểm tra trên mỗi lượt đặt |
| FR-10 | Admin có thể thay đổi thời gian cooldown toàn cục tại thời gian chạy qua dashboard |
| FR-11 | Dashboard admin hiển thị feed hoạt động gần đây với ô màu, tọa độ, Discord ID, IP, và timestamp, tự động làm mới mỗi 10 giây |
| FR-12 | Dashboard admin hiển thị thống kê thời gian thực: số client đang online, tổng lượt đặt, kích thước bảng, cooldown hiện tại, và preview canvas dạng base64 |
| FR-13 | Ngày kết thúc sự kiện có thể cấu hình (`EventEndDate`) khiến mọi lượt đặt sau deadline bị từ chối kèm thông báo |
| FR-14 | Trạng thái canvas, lệnh ban, milestone, và cấu hình tồn tại qua restart nhờ WAL và snapshot S3 của RaftDB |

## Yêu cầu phi chức năng

| ID | Yêu cầu |
|----|---------|
| NFR-01 | Pixel đã đặt đến mọi client đang kết nối trong vòng 500 ms ở tải bình thường (broadcast WebSocket qua thư viện `coder/websocket`) |
| NFR-02 | Mục tiêu availability production là 99,9 % mỗi tháng dương lịch, hỗ trợ bởi health check ECS Fargate và circuit breaker triển khai ALB có tự động rollback |
| NFR-03 | Không mất dữ liệu ghi đã xác nhận khi restart: WAL phân đoạn của RaftDB xác nhận bền vững mọi entry đã commit trước khi phản hồi Go server |
| NFR-04 | Canvas hỗ trợ kích thước tối đa 8.000 × 8.000 pixel (`MAX_DIMENSION` áp dụng trong Go, JavaScript, và C++) |
| NFR-05 | Mutation admin yêu cầu kiểm tra header same-origin (`requireSameOrigin` middleware) trước khi tra cứu danh sách admin cho phép, chống CSRF |
| NFR-06 | Token phiên là JWT ký HS256 lưu trong cookie httpOnly, sameSite=lax, scope theo domain cha; khóa ký nằm trong Secrets Manager và không bao giờ lộ dưới dạng biến môi trường plaintext |
| NFR-07 | Yêu cầu upgrade WebSocket được kiểm tra với danh sách `ALLOWED_ORIGINS`; yêu cầu không có header `Origin` (client không phải trình duyệt) được phép, tất cả còn lại kiểm tra khớp chính xác hoặc subdomain |
| NFR-08 | Toàn bộ môi trường production có thể tái tạo từ source: một `cdk deploy` tạo mọi tài nguyên; frontend được build và upload bởi pipeline CI |
| NFR-09 | Mỗi container ghi vào log stream CloudWatch riêng (tiền tố `awsplace` và `raftdb`); RaftDB có dashboard CloudWatch cho EFS I/O, kết nối client, và burst credits |
| NFR-10 | Ảnh container được quét bởi Trivy tìm CVE CRITICAL và HIGH trước khi publish ECR; phát hiện critical chặn pipeline; phát hiện high yêu cầu chủ sở hữu chấp nhận rõ ràng và ghi nhận theo commit SHA |
| NFR-11 | Idle timeout ALB được nâng lên 3.600 giây để giữ kết nối WebSocket lâu dài |
| NFR-12 | Thay thế task ECS dùng `minimumHealthyPercent: 0` để writer RaftDB đơn lẻ giải phóng khóa file EFS trước khi task thay thế chiếm lấy |

## Tiêu chí thành công

| ID | Tiêu chí | Cách xác minh |
|----|----------|---------------|
| SC-01 | User đã đăng nhập Discord đặt pixel và pixel đó hiện trên canvas của user thứ hai thời gian thực | Test thủ công với hai phiên trình duyệt trong staging |
| SC-02 | Milestone đã hẹn kích hoạt mở rộng bảng giữ nguyên mọi pixel hiện có và broadcast kích thước mới đến client | Test kích hoạt milestone trong stack staging với hình vẽ có sẵn |
| SC-03 | Admin có thể thực hiện mọi thao tác dashboard: mở rộng, hẹn milestone, xóa milestone, ban user, unban user, xóa vùng, điều chỉnh cooldown, xem feed hoạt động | Đi qua dashboard admin trên trang live |
| SC-04 | Toàn bộ stack deploy từ một lệnh `cdk deploy` trên nhánh `main` mà không cần thao tác thủ công trên AWS console | Chạy pipeline CI/CD end-to-end |
| SC-05 | Service sống sót qua restart task ECS bắt buộc mà không mất dữ liệu canvas | Kill task đang chạy, chờ task thay thế, so sánh canvas binary với snapshot S3 trước restart |
| SC-06 | Mọi bộ test tự động pass trong CI: test unit và integration Go, test Lambda Vitest, test parity nibble, test contract CDK, preset address-sanitizer và thread-sanitizer cho RaftDB | Pipeline CI xanh trên `main` |
| SC-07 | Ba hostname public (`place.namanhishere.com`, `ws.place.namanhishere.com`, `api.place.namanhishere.com`) resolve qua HTTPS với TLS certificate hợp lệ | Kiểm tra bằng trình duyệt và `curl` từ mạng ngoài |
| SC-08 | Mọi ảnh RaftDB publish lên ECR có file evidence Trivy chứng nhận không có lỗ hổng CRITICAL | Artifact CI lưu giữ 90 ngày |

## Dịch vụ AWS sử dụng

Quy tắc dự án yêu cầu tối thiểu ba dịch vụ AWS. **Dự án này dùng mười lăm.** Mỗi dòng dưới đây nêu vai trò thực tế của dịch vụ trong hệ thống này, lấy từ source CDK và xác nhận trên account live, không phải mô tả chung chung của dịch vụ.

| # | Dịch vụ | Vai trò trong awsplace |
|---|---------|----------------------|
| 1 | Amazon ECS on AWS Fargate | Chạy một task ứng dụng duy nhất: hai container, `App` (Go 1.25 WebSocket và canvas server, port 8980) và `RaftDb` (engine lưu trữ C++23, port 9100). Task size 1024 CPU units và 2048 MiB, `desiredCount: 1`. |
| 2 | Amazon ECR | Một repository, `awsplace-ecs`, chứa cả hai ảnh container. Tag mutability là `MUTABLE_WITH_EXCLUSION` với filter `raftdb-*`, nên chỉ tag của storage engine là bất biến; scan-on-push bật và giữ mười ảnh gần nhất. |
| 3 | Amazon EFS | Nơi lưu trữ bền vững cho WAL của RaftDB và snapshot cục bộ. |
| 4 | Amazon S3 | Một bucket do stack sở hữu nhận snapshot engine RaftDB mỗi 300 giây; hai bucket khác cho canvas binary và PNG export được import theo tên thay vì tạo mới. |
| 5 | AWS Lambda | Một handler Node.js 24 Express thực hiện đổi mã Discord OAuth, ký cookie phiên HS256, trả lời `/api/me`, và proxy lệnh admin đến ALB. |
| 6 | Amazon API Gateway | HTTP API v2, cửa trước public cho `/auth/*` và `/api/*`, đứng sau domain tùy chỉnh `api.place.namanhishere.com`. |
| 7 | Elastic Load Balancing (ALB) | Application Load Balancer public chấm dứt HTTPS trên 443 và chuyển tiếp đến target group port 8980 với health check `/health`. Idle timeout nâng lên 3600 giây vì kết nối mang theo là WebSocket lâu dài. |
| 8 | Amazon Route 53 | Hosted zone `place.namanhishere.com`. Record `api.` được tạo trong stack, record `ws.` cũng vậy; Amplify tự tạo record apex, nên ba hostname được phục vụ bởi hai record do CloudFormation quản lý. |
| 9 | AWS Certificate Manager | Cấp certificate wildcard, trong vùng stack `ap-southeast-1`, dùng cho hostname `api.` và `ws.`. Amplify tạo certificate riêng cho apex. |
| 10 | AWS Secrets Manager | Chứa secret. Người đọc runtime duy nhất là container ECS `App`, nhận `SESSION_SECRET` dưới dạng tham chiếu secret ECS chứ không phải biến môi trường plaintext. |
| 11 | AWS Amplify Hosting | Phục vụ frontend tĩnh đã build. Nó sở hữu record DNS apex và certificate TLS riêng. |
| 12 | Amazon CloudWatch | Thu thập một log stream mỗi container, tiền tố `raftdb` và `awsplace`, và chứa dashboard đồng thuận Raft dùng để theo dõi storage engine. |
| 13 | AWS IAM | Ba vai trò với policy inline có scope: ECS task execution, ECS task, và Lambda execution. Mục 2.5 trình bày chi tiết các policy statement. |
| 14 | AWS STS | Cấp credentials ngắn hạn cho pipeline triển khai. Mỗi job CI có credentials gọi `assume-role-with-web-identity` với token OIDC do GitLab cấp và phiên 3600 giây. |
| 15 | AWS CloudFormation, qua CDK | Nền tảng triển khai. Một stack, `AwsplaceStack`, tổng hợp từ TypeScript; mọi tài nguyên trên đều là thành viên của nó. |

## Giới hạn chấp nhận trong thiết kế này

Ba giới hạn, nêu rõ ở đây thay vì giấu trong code.

Production chạy **một Raft voter**, không phải quorum. `desiredCount: 1` và một access point EFS duy nhất có nghĩa là cấu hình multi-voter mà storage engine hỗ trợ không được sử dụng trên production; code rõ ràng rằng chế độ single-node không phải là câu chuyện về durability. Cấu hình ba voter tồn tại trong một stack staging riêng và được mô tả là mục tiêu đã ghi nhận, không phải trạng thái hiện tại.

**Cooldown lưu trong bộ nhớ** trong process Go và mất khi task restart, nên người dùng tạm thời lấy lại khả năng đặt ngay sau khi redeploy.
