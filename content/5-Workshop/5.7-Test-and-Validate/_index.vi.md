---
title: "Kiểm thử & Xác thực"
date: 2024-01-01
weight: 6
chapter: false
pre: " <b> 5.7. </b> "
---

Chúng mình tin rằng kiểm thử là nền tảng của dự án awsplace. Thay vì chỉ cầu mong mọi thứ hoạt động suôn sẻ, chúng mình kiểm tra code ở nhiều mức độ khác nhau — từ các unit test nhỏ lẻ, đến kiểm thử hạ tầng CDK, và cuối cùng là đưa mọi thứ qua các pipeline CI/CD.

Dưới đây là cách chúng mình tổ chức các bài kiểm thử:

| Phần con | Mô tả |
|---|---|
| [5.7.1 Kiểm thử Hạ tầng CDK](5.7.1-cdk-infrastructure-testing/) | Dùng Jest để tạo ra các template CloudFormation thực tế và đảm bảo hạ tầng được cấu hình chuẩn xác |
| [5.7.2 Kiểm thử Ứng dụng](5.7.2-application-testing/) | Unit test cho code Go, kết hợp với integration test cho PostgreSQL và MiniStack (DynamoDB + S3) |
| [5.7.3 Xác thực Pipeline CI/CD](5.7.3-ci-cd-pipeline-validation/) | Các luồng GitHub Actions và GitLab CI tự động kiểm tra code trước mỗi lần deploy |

#### Triết lý Kiểm thử

Khi viết test, quy tắc cốt lõi của chúng mình là **kiểm thử hợp đồng (contract), thay vì kiểm thử cách triển khai chi tiết**. Thay vì đi mock từng tài nguyên CDK một cách máy móc, chúng mình chọn cách tiếp cận thực tế hơn:

1. **Tạo template thực tế**: Đầu tiên, chúng mình chạy **cdk synth** để sinh ra các template CloudFormation y hệt như lúc deploy thật.
2. **Kiểm tra đầu ra cuối cùng**: Sau đó, chúng mình đọc file JSON được sinh ra để đảm bảo mọi tài nguyên, cấu hình, và export quan trọng đều xuất hiện đầy đủ.
3. **Xác minh script triển khai**: Cuối cùng, chúng mình kiểm tra các script deploy để chắc chắn rằng chúng khớp với những gì sẽ chạy trên CI/CD.

Bằng cách kiểm tra kết quả thực tế, chúng mình có thể phát hiện ra những lỗi deploy mà kiểu mock truyền thống hay bỏ sót.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Sơ đồ kim tự tháp kiểm thử (testing pyramid) của dự án awsplace:
- Đỉnh: CI/CD Pipeline (GitHub Actions / GitLab CI)
- Giữa: CDK Contract Tests (Jest)
- Đáy: Application Tests (Go unit + integration)
Lưu tại: static/images/5.6/testing-pyramid.png
-->
