---
title: "Tổng quan Workshop"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.1. </b> "
---

## Workshop này là gì

Workshop này đi qua từng bước vận hành cần thiết để triển khai, kiểm thử, giám sát và tháo dỡ **awsplace** — từ một tài khoản AWS trống đến một trang production đang chạy. Workshop được viết cho những ai muốn tái tạo toàn bộ môi trường từ source, không chỉ đọc cho biết. Mỗi phần tương ứng với một giai đoạn trong vòng đời triển khai: chuẩn bị, cấu trúc hạ tầng dạng code, pipeline CI/CD, triển khai, kiểm thử, giám sát và dọn dẹp.

Workshop giả định bạn đã quen thuộc cơ bản với AWS, Docker và dòng lệnh. Không yêu cầu kinh nghiệm trước với CDK, ECS Fargate hoặc WebSocket server.

## Kiến trúc tổng quan

Kiến trúc đã triển khai phục vụ ba luồng lưu lượng qua ba hostname public, tất cả được resolve bởi một Route 53 hosted zone:

| Luồng | Hostname | Đích | Mục đích |
|---|---|---|---|
| Frontend | `place.namanhishere.com` | AWS Amplify Hosting | HTML, CSS và JavaScript tĩnh được phục vụ qua CDN toàn cầu của Amplify |
| Xác thực | `api.place.namanhishere.com` | API Gateway HTTP API → Lambda | Callback Discord OAuth2, ký cookie phiên, endpoint nhận diện `/api/me` |
| Backend | `ws.place.namanhishere.com` | ALB → ECS Fargate | Kết nối WebSocket lâu dài cho broadcast pixel thời gian thực |

Mọi tài nguyên AWS trong kiến trúc này được tạo bởi một lệnh `cdk deploy` duy nhất. Không có gì được tạo thủ công trong console.

![Kiến trúc Hạ tầng](/images/archtechture.png)

## Các phần của workshop

| # | Phần | Nội dung |
|---|------|----------|
| 5.2 | [Chuẩn bị](5.2-Prerequisites/) | Cài đặt phần mềm, thiết lập tài khoản AWS, quyền IAM, ứng dụng Discord, ủy quyền DNS, cấu hình OIDC, biến môi trường và xác minh |
| 5.3 | [Cấu trúc Dự án CDK](5.3-CDK-Project-Structure/) | 15 module TypeScript tạo nên `AwsplaceStack`: điểm vào, mạng VPC, DynamoDB, ECS Fargate, ECR, IAM, Lambda, API Gateway, Amplify, Route 53 và hạ tầng RaftDB |
| 5.4 | [Pipeline CI/CD](5.4-CICD-Pipeline/) | Thiết lập CI kép với GitHub Actions và GitLab CI, xác thực OIDC, ma trận kiểm thử, build Docker image với quy trình custody, và trình tự triển khai |
| 5.5 | [Triển khai Hạ tầng](5.5-Deploy-Infrastructure/) | Chạy `cdk deploy` để cấp phát toàn bộ stack AWS, chuẩn bị stack cho trạng thái lỗi và luồng triển khai |
| 5.6 | [Triển khai Frontend](5.6-Deploy-Frontend/) | Build frontend tĩnh với thay thế token, upload lên Amplify qua URL S3 có chữ ký và xác minh triển khai |
| 5.7 | [Kiểm thử & Xác thực](5.7-Test-and-Validate/) | Test hợp đồng CDK với Jest, test unit và integration Go, và xác thực pipeline CI/CD |
| 5.8 | [Giám sát](5.8-Monitoring/) | Dashboard CloudWatch cho metric Raft và EFS, cảnh báo cho CPU, bộ nhớ và snapshot cũ, kiểm tra sức khỏe và log tập trung |
| 5.9 | [Dọn dẹp](5.9-Cleanup/) | Thiết kế chính sách xóa tài nguyên, quy trình `cdk destroy` và dọn dẹp thủ công dữ liệu được giữ lại |

## Bạn sẽ có gì ở cuối cùng

Sau khi hoàn thành mọi phần theo thứ tự, bạn sẽ có:

- Một **trang public đang chạy** tại domain bạn chọn, được host bởi AWS Amplify Hosting, với endpoint WebSocket phía sau ALB và bề mặt xác thực trên API Gateway
- **Mọi tài nguyên AWS** được tạo bởi một lệnh `cdk deploy` duy nhất — không có gì được tạo thủ công trong console
- Một **pipeline CI/CD** trên cả GitHub Actions và GitLab CI tự động kiểm thử, build, quét và triển khai mỗi khi push lên `main`
- **Giám sát và cảnh báo** qua dashboard và cảnh báo CloudWatch, tất cả được định nghĩa trong CDK và kiểm thử trước khi triển khai
- Một **lộ trình dọn dẹp sạch** giúp tháo dỡ stack đang chạy mà không xóa dữ liệu được giữ lại trừ khi bạn chọn xóa

## Dịch vụ AWS sử dụng

Workshop triển khai trên **mười lăm dịch vụ AWS**. Mỗi dịch vụ được giới thiệu tại phần nơi nó lần đầu được tạo hoặc cấu hình:

| # | Dịch vụ | Vai trò trong awsplace | Giới thiệu tại |
|---|---------|------------------------|-----------------|
| 1 | Amazon ECS on AWS Fargate | Chạy một task ứng dụng duy nhất: hai container, `App` (WebSocket server Go 1.25) và `RaftDb` (engine lưu trữ C++23) | 5.3 Cấu trúc Dự án CDK |
| 2 | Amazon ECR | Một repository, `awsplace-ecs`, chứa cả hai ảnh container với scan-on-push bật | 5.3 Cấu trúc Dự án CDK |
| 3 | Amazon EFS | Nơi lưu trữ bền vững cho WAL của RaftDB và snapshot cục bộ | 5.3 Cấu trúc Dự án CDK |
| 4 | Amazon S3 | Bucket snapshot cho engine RaftDB; bucket được import cho canvas binary và PNG export | 5.2 Chuẩn bị |
| 5 | AWS Lambda | Handler Node.js 24 xử lý đổi mã Discord OAuth2, ký cookie phiên và `/api/me` | 5.3 Cấu trúc Dự án CDK |
| 6 | Amazon API Gateway | HTTP API v2, cửa trước public cho `/auth/*` và `/api/*` | 5.3 Cấu trúc Dự án CDK |
| 7 | Elastic Load Balancing (ALB) | ALB public chấm dứt HTTPS, chuyển tiếp lưu lượng WebSocket đến ECS trên port 8980 | 5.3 Cấu trúc Dự án CDK |
| 8 | Amazon Route 53 | Hosted zone cho domain tùy chỉnh; tạo record alias `api.` và `ws.` | 5.2 Chuẩn bị |
| 9 | AWS Certificate Manager | Certificate wildcard cho `*.domain`, được dùng chung bởi ALB và API Gateway | 5.3 Cấu trúc Dự án CDK |
| 10 | AWS Secrets Manager | Chứa secret Discord client và khóa ký phiên; không bao giờ lộ dưới dạng biến môi trường plaintext | 5.3 Cấu trúc Dự án CDK |
| 11 | AWS Amplify Hosting | Phục vụ frontend tĩnh đã build; sở hữu record DNS apex và certificate TLS riêng | 5.6 Triển khai Frontend |
| 12 | Amazon CloudWatch | Log stream mỗi container, dashboard đồng thuận Raft và cảnh báo vận hành | 5.8 Giám sát |
| 13 | AWS IAM | Ba vai trò với policy inline có scope: ECS task execution, ECS task và Lambda execution | 5.2 Chuẩn bị |
| 14 | AWS STS | Credentials ngắn hạn cho pipeline triển khai qua liên kết OIDC | 5.4 Pipeline CI/CD |
| 15 | AWS CloudFormation | Nền tảng triển khai; một stack, `AwsplaceStack`, tổng hợp từ TypeScript | 5.5 Triển khai Hạ tầng |

## Chuẩn bị nhanh

Trước khi bắt đầu, bạn cần:

| Yêu cầu | Chi tiết |
|----------|----------|
| Tài khoản AWS | Có quyền administrator trong `ap-southeast-1` |
| Domain | Một subdomain được ủy quyền sang Route 53 (ví dụ: `place.namanhishere.com`) |
| Ứng dụng Discord | Client OAuth2 với scope `identify` và redirect URI trỏ đến API Gateway của bạn |
| Instance GitLab | Tự host tại URL đã biết, với runner CI/CD được cấu hình cho OIDC |
| Repository GitHub | Có Actions bật và OIDC provider được cấu hình trong AWS IAM |
| Phần mềm | Node.js 24+, Go 1.25+, Docker 27+, AWS CLI v2, CDK CLI |

Phần [5.2 Chuẩn bị](5.2-Prerequisites/) trình bày chi tiết từng yêu cầu, kèm lệnh xác minh để đảm bảo mọi thứ đã sẵn sàng trước khi bạn push commit đầu tiên.
