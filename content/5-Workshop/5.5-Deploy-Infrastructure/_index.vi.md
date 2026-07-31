---
title: "Deploy Hạ Tầng"
date: 2024-01-01
weight: 5
chapter: false
pre: " <b> 5.5. </b> "
---

## Deploy Hạ Tầng với AWS CDK

Toàn bộ hạ tầng cho **awsplace** được quản lý dưới dạng code bằng **AWS Cloud Development Kit (CDK)**, viết bằng TypeScript. Cách tiếp cận Infrastructure as Code (IaC) này đảm bảo mọi tài nguyên cloud đều được quản lý phiên bản, có thể lặp lại và kiểm toán được. Toàn bộ kiến trúc nằm gọn trong một CDK construct duy nhất tên **AwsplaceStack**, đóng vai trò là bản thiết kế tổng thể cho ứng dụng.

### Kiến Trúc Tổng Thể

Kiến trúc được deploy được thiết kế nhằm đảm bảo khả năng mở rộng, tính bảo mật và sự phân chia trách nhiệm rõ ràng. Dưới đây là cái nhìn tổng quan về cách các thành phần tương tác với nhau.

![Kiến Trúc Hạ Tầng](/images/archtechture.png)

Luồng hoạt động chia thành ba đường chính:

- **Đường frontend:** Trình duyệt người dùng phân giải tên miền qua Route 53, từ đó chuyển hướng traffic đến AWS Amplify để phục vụ nội dung tĩnh.
- **Đường xác thực:** Khi người dùng nhấn "Đăng nhập", yêu cầu đi qua API Gateway đến Lambda function xử lý luồng OAuth2 với Discord, đọc client secret từ Secrets Manager tại thời điểm chạy.
- **Đường backend:** Kết nối WebSocket được định tuyến qua Route 53 đến Application Load Balancer, từ đó chuyển tiếp đến các ECS Fargate task. Mỗi task chạy **hai container** — Go application server và RaftDB sidecar. Trong production (chế độ **raftdb-only**), Go server giao tiếp với RaftDB sidecar qua **localhost:9100** cho mọi thao tác đọc/ghi. RaftDB lưu trữ WAL và dữ liệu consensus vào **EFS**, đồng thời định kỳ ghi snapshot vào một **S3 Snapshot Bucket** riêng. Tên bảng DynamoDB và tên S3 canvas/exports bucket được truyền dưới dạng biến môi trường cho Go server cho các tài nguyên đã provision.

### AwsplaceStack: Phân Tích Chuyên Sâu

**AwsplaceStack** là construct trung tâm trong ứng dụng CDK. Nó kết hợp nhiều construct nhỏ hơn theo dạng module — mỗi construct chịu trách nhiệm quản lý một phần cụ thể của hạ tầng.

#### 1. Mạng

- **VPC:** Một Virtual Private Cloud tùy chỉnh cung cấp môi trường mạng cô lập cho tất cả tài nguyên. VPC trải rộng trên **2 Availability Zone** để đảm bảo tính dự phòng.
- **Subnets:** VPC chỉ sử dụng **public subnet** và không có NAT Gateway (**natGateways: 0**). Đây là quyết định tối ưu chi phí có chủ đích — tất cả dịch vụ cần truy cập internet (ECS Fargate, ALB) đều chạy trong public subnet với public IP tự gán. Bảo mật được thực thi ở tầng security group thay vì qua topology mạng.

#### 2. Lưu trữ

Ứng dụng sử dụng ba S3 bucket và một EFS file system:

**S3 Buckets** (import theo tên bucket, không tạo mới):

- **awsplace-canvas-{account}**: Lưu trữ trạng thái chính của canvas.
- **awsplace-exports-{account}**: Lưu trữ dữ liệu xuất ra.

**Lưu trữ RaftDB** (tạo mới với cấu hình bảo mật đầy đủ):

- **RaftDB Snapshot Bucket**: Có versioning, mã hóa (S3-managed), bắt buộc SSL/TLS 1.2, chặn mọi truy cập công khai. Phiên bản không còn hiện tại tự động hết hạn sau 35 ngày.
- **EFS File System**: Một Elastic File System được mã hóa cung cấp lưu trữ bền vững cho dữ liệu consensus của RaftDB. Một access point giới hạn quyền ghi vào **/raftdb/production/member-1** với quyền POSIX bị hạn chế (UID/GID 10001, mode 0750).

#### 3. Kho chứa Container

Một kho chứa Amazon ECR tên **awsplace-ecs** lưu trữ Docker image cho Go backend server. Pipeline CI/CD push image có gắn tag vào đây, và ECS Fargate pull chúng khi deploy.

#### 4. IAM Roles

Stack tuân thủ **nguyên tắc đặc quyền tối thiểu** — mỗi dịch vụ chỉ nhận được quyền hạn mà nó thực sự cần:

- **EcsTaskRole**: Cấp quyền cho task đang chạy truy cập DynamoDB, S3 và EFS. Cũng bao gồm quyền đọc/ghi RaftDB snapshot bucket, giới hạn phạm vi ở **production/member-1/*** .
- **EcsTaskExecutionRole**: Cho phép ECS agent pull image từ ECR, đọc secret từ Secrets Manager và gửi log đến CloudWatch.
- **LambdaExecutionRole**: Cấp cho Lambda xác thực quyền thực thi cơ bản.

#### 5. Backend Lõi

Đây là construct lớn nhất và quan trọng nhất:

- **ECS Cluster**: Cung cấp lớp điều phối cho tất cả container backend.
- **Fargate Task Definition**: Chỉ định Docker image, phân bổ CPU/bộ nhớ, IAM role, biến môi trường (tên bảng, tên bucket, domain) và secret (inject từ Secrets Manager khi container khởi động). Task chạy **hai container** — Go application server và RaftDB sidecar, chia sẻ một EFS volume cho trạng thái consensus.
- **Application Load Balancer (ALB)**: Nằm trong public subnet, lắng nghe trên cả HTTP (port 80, redirect sang HTTPS) và HTTPS (port 443 với wildcard TLS cert). Định tuyến traffic đến ECS task trên port 8980. Health check path, stickiness và deregistration delay đều được cấu hình phù hợp với WebSocket.
- **Security Groups**: Security group của ALB cho phép HTTP/HTTPS từ mọi nơi. Security group của ECS chỉ cho phép port 8980 từ ALB — không có truy cập internet trực tiếp đến container. EFS chỉ cho phép NFS từ ECS security group.
- **Bản ghi Route 53 A**: Một alias record cho **ws.{domainName}** trỏ trực tiếp đến ALB.
- **Deployment Circuit Breaker**: ECS được cấu hình với circuit breaker tự động rollback nếu task mới không thể ổn định.

> **[SCREENSHOT: Giao diện AWS ECS console hiển thị dịch vụ 'awsplace' đang chạy và các task liên quan]**

#### 6. Xác thực

- **Hàm Lambda**: Một hàm Node.js 24 xử lý luồng OAuth2 callback với Discord. Nó đọc client secret từ **Secrets Manager** tại runtime — secret không bao giờ được đóng gói vào deployment artifact.
- **API Gateway**: Một HTTP API (không phải REST API) ánh xạ các route dưới **/auth/** đến hàm Lambda. Một custom domain **api.{domainName}** được gắn với API, sử dụng wildcard ACM certificate chung. Bản ghi Route 53 trỏ subdomain này đến API Gateway.
- **Secrets Manager**: Lưu trữ Discord client secret, session secret và các cấu hình nhạy cảm khác dưới dạng JSON object. Cả Lambda function và ECS task đều có thể đọc secret này (với quyền truy cập theo IAM scope).

#### 7. Frontend

- **Ứng dụng AWS Amplify**: Được cấu hình cho **deploy thủ công** — không kết nối Git repository. Pipeline CI/CD build frontend và upload file zip trực tiếp lên Amplify. Điều này tách rời frontend hosting khỏi bất kỳ nhà cung cấp source control cụ thể nào.
- **Tên miền tùy chỉnh**: Root domain (ví dụ: **place.namanhishere.com**) được ánh xạ đến nhánh **production**. Amplify tự cung cấp và quản lý chứng chỉ TLS riêng cho domain này — tách biệt với wildcard ACM cert được ALB và API Gateway sử dụng.
- **Luật Rewrite SPA**: Một custom rewrite rule viết lại các path không có phần mở rộng thành **/index.html**, đồng thời giữ nguyên quyền truy cập trực tiếp đến các file có phần mở rộng (CSS, JS, image) và đặc biệt là **/admin.html**. Một catch-all 404 rewrite cũng phục vụ **/index.html** cho các path không xác định.

#### 8. DNS & Chứng chỉ

- **Hosted Zone**: Stack import một hosted zone Route 53 đã có sẵn theo ID (không tạo mới).
- **Wildcard ACM Certificate**: Một chứng chỉ cho **\*.{domainName}** được cung cấp và xác thực qua DNS. Cert này được chia sẻ bởi ALB (cho subdomain **ws.**) và API Gateway (cho subdomain **api.**). Amplify quản lý cert riêng cho root domain.

#### 9. CloudWatch Dashboard

Một CloudWatch dashboard được tự động cung cấp với các metric vận hành cho ECS service, ALB, DynamoDB table và Lambda function. Điều này giúp team có cái nhìn tổng quan trên một bảng điều khiển duy nhất để giám sát sức khỏe ứng dụng trong môi trường production.

---

### Quy Trình Deploy trong CI/CD

Logic deploy, được điều phối bởi GitHub Actions trong job **deploy**, tuân theo trình tự chính xác để đưa hạ tầng vào hoạt động một cách an toàn.

1. **Kiểm tra Môi trường:** Quá trình bắt đầu với **scripts/validate-deploy-env.sh**, xác minh tất cả biến bí mật và cấu hình bắt buộc (như **DISCORD_CLIENT_ID**, **HOSTED_ZONE_ID**, **RAFTDB_IMAGE_DIGEST**) đều có mặt và đúng định dạng. Nếu thiếu bất cứ thứ gì, pipeline dừng ngay — không có deploy nửa vời.

2. **Chuẩn bị Stack:** **scripts/prepare-cloudformation-deploy.sh** kiểm tra trạng thái hiện tại của CloudFormation stack. Nếu phát hiện trạng thái lỗi hoặc đã rollback (như **CREATE_FAILED** hoặc **ROLLBACK_COMPLETE**), script tự động xóa stack hỏng để CDK có thể deploy mới. Nếu stack ở trạng thái **UPDATE_ROLLBACK_FAILED**, script từ chối tiếp tục — tình huống đó cần can thiệp thủ công.

3. **Deploy bằng CDK:** Khi môi trường đã được xác thực, lệnh cốt lõi được thực thi:

**npx cdk deploy --require-approval never --no-strict --all --import-existing-resources**

CDK tổng hợp các TypeScript construct thành CloudFormation template và deploy tất cả tài nguyên. Flag **--import-existing-resources** cho phép CDK tái adopt các resource có physical name rõ ràng nếu stack được tạo lại sau failure.

> ![AwsplaceStack trong CloudFormation](/images/5-Workshop/5.5-Deploy-Infrastructure/Screenshot%202026-07-27%20194430.png)

4. **Deploy Frontend trên Amplify:** Sau khi hạ tầng backend ổn định, pipeline đóng gói static asset từ **dist/** thành file zip và upload trực tiếp lên Amplify qua pre-signed S3 URL. (Quy trình này được trình bày chi tiết ở phần tiếp theo.)

5. **Cập nhật ECS Service:** Cuối cùng, **aws ecs update-service --force-new-deployment** kích hoạt rolling update. ECS drain các task cũ và khởi chạy task mới với Docker image và cấu hình đã cập nhật. Deployment circuit breaker đảm bảo tự động rollback nếu task mới không thể ổn định.