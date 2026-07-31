---
title : "Cấu trúc Dự án CDK"
date : 2024-01-01
weight : 4
chapter : false
pre : " <b> 5.3. </b> "
---

Lớp mã CDK (AWS Cloud Development Kit) là nơi chứa toàn bộ cấu hình hạ tầng cho **awsplace**. Chúng mình dùng **TypeScript** để tận dụng tính năng kiểm tra lỗi chặt chẽ của nó. Phần này thiết lập mọi thứ mà ứng dụng cần để chạy: mạng, tính toán, cơ sở dữ liệu, lưu trữ, xác thực, DNS và giám sát. Thay vì viết tất cả vào một chỗ, chúng mình chia nhỏ thành **15 module TypeScript** trong thư mục **cdk/**. Tất cả sẽ được liên kết với nhau bằng một file chính duy nhất để triển khai toàn bộ hạ tầng lên khu vực **ap-southeast-1** (Singapore).

Dưới đây là cách chúng mình tổ chức cấu trúc của dự án:

| Phần con | Mô tả |
|---|---|
| [5.3.1 Điểm vào & Kết hợp Stack](5.3.1-entry-point/) | File chính kết nối tất cả các module lại với nhau theo đúng thứ tự (Bao gồm: CDK App, AwsplaceStack, RaftDbStagingStack) |
| [5.3.2 VPC & Mạng](5.3.2-vpc-networking/) | Thiết lập mạng dùng public subnets và không dùng NAT Gateway để tiết kiệm chi phí (Bao gồm: VPC, subnets, security groups) |
| [5.3.3 Lớp Cơ sở dữ liệu DynamoDB](5.3.3-database-dynamodb/) | Thiết kế single-table đơn giản với khóa kết hợp (Bao gồm: 4 bảng DynamoDB TableV2 dạng on-demand) |
| [5.3.4 Lớp Tính toán ECS Fargate](5.3.4-ecs-compute/) | Nơi chạy ứng dụng Go và RaftDB đằng sau HTTPS load balancer (Bao gồm: Fargate cluster, task definitions, ALB) |
| [5.3.5 Lưu trữ: ECR & S3](5.3.5-storage-ecr/) | Nơi lưu Docker image và các file của ứng dụng (Bao gồm: ECR repository, 2 bucket S3 được import vào) |
| [5.3.6 IAM Roles & Bảo mật](5.3.6-iam-security/) | Phân quyền vừa đủ (least-privilege) cho các container và Lambda (Bao gồm: 3 IAM roles) |
| [5.3.7 Lambda, API Gateway & Amplify](5.3.7-lambda-apigw-amplify/) | Chứa các hàm xử lý xác thực và chỗ host frontend (Bao gồm: Lambda, HTTP API v2, Amplify app) |
| [5.3.8 Cơ sở hạ tầng RaftDB & Route 53](5.3.8-raftdb-route53/) | Cấu hình DNS, chứng chỉ bảo mật và môi trường staging cho RaftDB (Bao gồm: Route 53, ACM cert, staging stack) |

#### Triết lý Thiết kế CDK

Khi viết mã CDK cho awsplace, chúng mình tuân theo một vài quy tắc cốt lõi để giữ cho code luôn gọn gàng và dễ bảo trì:

1. **Dùng hàm thay vì class**: Thay vì dùng tính kế thừa phức tạp của class, mỗi module chỉ export ra một hàm **create*()** đơn giản. Nó nhận đầu vào và trả về đúng những gì nó tạo ra, giúp việc đọc hiểu code dễ dàng hơn nhiều.
2. **TypeScript nghiêm ngặt**: Chúng mình bật chế độ kiểm tra nghiêm ngặt (**strict: true**) để phát hiện ngay các lỗi gõ nhầm hay thiếu cấu hình từ trước khi chạy **cdk synth**.
3. **Export những thông tin cần thiết**: Những thứ quan trọng như tên bảng, tên bucket, hay ARN đều được xuất ra bằng **CfnOutput** để các pipeline CI/CD có thể dễ dàng lấy và sử dụng sau này.
4. **Chỉ import S3 bucket**: Thay vì tạo S3 bucket trực tiếp trong stack, chúng mình import chúng thông qua tên. Nhờ vậy, nếu lỡ có chạy lệnh **cdk destroy** xóa stack, dữ liệu trong bucket vẫn sẽ được an toàn.
5. **Không dùng chuỗi ARN cứng**: Chúng mình không bao giờ tự gõ tay các chuỗi ARN. Thay vào đó là dùng các hàm có sẵn của CDK, đảm bảo ARN luôn chính xác cho dù bạn deploy ở account hay region nào.
6. **Bảo vệ tài nguyên quan trọng**: Với những thứ không muốn bị mất (như database hay secret), chúng mình gán thêm **RemovalPolicy.RETAIN**. Nhờ đó, việc xóa stack sẽ không vô tình làm mất các dữ liệu quan trọng.

