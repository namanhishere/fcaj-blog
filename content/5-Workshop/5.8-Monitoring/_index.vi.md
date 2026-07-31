---
title: "Giám sát"
date: 2024-01-01
weight: 7
chapter: false
pre: " <b> 5.8. </b> "
---

Với awsplace, chúng mình đã xây dựng một hệ thống giám sát đa tầng để luôn nắm rõ tình hình hệ thống. Chúng mình dùng CloudWatch dashboard để theo dõi trực quan, dùng alarm để tự động cảnh báo lỗi, cấu hình health check để giữ container luôn chạy ổn định, và gom toàn bộ log về một chỗ để dễ dàng bắt lỗi. Tất cả những thứ này đều được code thẳng vào CDK, nên bạn không cần phải tốn công bấm click trên AWS console — và tất nhiên, chúng cũng được tự động test kỹ càng trước khi deploy.

Dưới đây là cách chúng mình thiết lập hệ thống giám sát:

| Phần con | Mô tả |
|---|---|
| [5.8.1 CloudWatch Dashboards](5.8.1-cloudwatch-dashboards/) | Các bảng theo dõi metric của Raft, bộ nhớ EFS, mức sử dụng CPU/RAM, và tình trạng của Load Balancer |
| [5.8.2 CloudWatch Alarms](5.8.2-cloudwatch-alarms/) | Tự động báo động khi CPU/RAM quá tải, lỗi lưu dữ liệu, deploy thất bại, hoặc container bị ngưng hoạt động |
| [5.8.3 Health Check Container & Ứng dụng](5.8.3-health-checks/) | Đảm bảo container luôn khoẻ mạnh bằng các lệnh kiểm tra của ECS và ALB, kèm theo quy tắc khởi động |
| [5.8.4 Centralized Logging](5.8.4-centralized-logging/) | Gom nhóm và lưu trữ mọi log vào CloudWatch để dễ dàng tìm kiếm khi cần debug |

#### Triết lý Giám sát

Cách tiếp cận của chúng mình rất đơn giản: **chỉ giám sát những thứ thực sự làm hỏng hệ thống**. Thay vì tạo ra một đống dashboard rối mắt với đủ loại metric, chúng mình chỉ tập trung vào những gì quan trọng nhất:

1. **Theo dõi những gì thiết yếu**: Chúng mình theo dõi các metric riêng của Raft từ các node database (gắn tag **Cluster** và **NodeId**) để biết chính xác node nào đang làm gì.
2. **Báo động nguy cơ mất dữ liệu**: Chúng mình cài cảnh báo cho các vấn đề liên quan đến lưu trữ — như snapshot quá cũ hoặc lỗi ghi dữ liệu — vì mất dữ liệu là rủi ro lớn nhất.
3. **Phát hiện lỗi khi deploy**: Nếu CPU của một container luôn ở mức thấp bất thường sau khi deploy, chúng mình sẽ báo động ngay vì khả năng cao là ứng dụng chưa khởi động lên được.
4. **Bỏ qua dữ liệu trống một cách an toàn**: Chúng mình coi việc "thiếu dữ liệu" là bình thường với hầu hết các cảnh báo. Nhờ vậy, khi mới tạo stack, chúng mình không bị spam cảnh báo giả chỉ vì hệ thống chưa kịp đẩy dữ liệu lên.

Cách làm này giúp dashboard của chúng mình luôn gọn gàng và cảnh báo luôn hữu ích. Mỗi khi có tiếng báo động, chúng mình biết ngay cần phải sửa gì.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Sơ đồ các tầng giám sát của dự án awsplace:
- Trên cùng: CloudWatch Dashboards (trực quan hoá thời gian thực)
- Giữa: CloudWatch Alarms (cảnh báo tự động)
- Dưới cùng: Health Checks + Centralized Logging (chẩn đoán cấp dịch vụ)
Lưu tại: static/images/5.7/monitoring-layers.png
-->
