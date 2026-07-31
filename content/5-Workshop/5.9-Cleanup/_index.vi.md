---
title: "Dọn dẹp Tài nguyên"
date: 2024-01-01
weight: 8
chapter: false
pre: " <b> 5.9. </b> "
---

Trong dự án awsplace, chúng mình coi việc dọn dẹp hệ thống là một nhiệm vụ quan trọng chứ không phải là chuyện làm cho có. Chúng mình đã thiết lập **RemovalPolicy** rõ ràng cho từng tài nguyên CDK, viết sẵn hướng dẫn chi tiết cách xoá stack, và đảm bảo rằng muốn xóa các dữ liệu quan trọng thì phải có sự phê duyệt thủ công. Phần này sẽ trình bày cách chúng mình quản lý vòng đời của các tài nguyên từ lúc được tạo ra cho đến khi bị xoá bỏ an toàn.

Dưới đây là cách chúng mình tổ chức quy trình dọn dẹp:

| Phần con | Mô tả |
|---|---|
| [5.9.1 Thiết kế Chính sách Xoá Tài nguyên](5.9.1-removal-policy-design/) | Lý do chúng mình chọn giữ lại (RETAIN) hay xoá đi (DESTROY) cho từng tài nguyên như ECR, EFS, S3, và Secret |
| [5.9.2 Quy trình Huỷ Stack](5.9.2-stack-destruction/) | Hướng dẫn từng bước cách xoá các stack môi trường staging và production, cùng cách dọn dẹp trên CI/CD |
| [5.9.3 Dọn dẹp Dữ liệu Được Giữ lại](5.9.3-retained-data-cleanup/) | Các bước thực hiện thủ công để xoá an toàn những dữ liệu quan trọng, dọn dẹp S3 version và tài nguyên EFS |

#### Triết lý Dọn dẹp

Khi nói đến việc dọn dẹp, quy tắc lớn nhất của chúng mình là **tách biệt việc xoá stack khỏi việc xoá dữ liệu**:

1. **Xoá stack chỉ là gỡ bỏ ứng dụng đang chạy**: Khi chạy lệnh **cdk destroy**, hệ thống chỉ tháo dỡ các tài nguyên tính toán như ECS service, load balancer, và security group.
2. **Xóa dữ liệu là thao tác thủ công**: Việc thực sự xoá đi dữ liệu là một quy trình hoàn toàn tách biệt, đòi hỏi phải được phê duyệt và chạy lệnh thủ công. Việc xóa stack sẽ không bao giờ tự động xóa dữ liệu của bạn.
3. **Giữ lại những thứ quan trọng**: Chúng mình cấu hình để CDK luôn giữ lại các tài nguyên sinh tử (như ECR repo, snapshot của RaftDB, file trên EFS, và secret). Chúng sẽ vẫn tồn tại kể cả khi stack đã bị xoá, vì chúng mình cần chúng sống sót qua các lần deploy.

Sự tách biệt này mang lại sự an tâm tuyệt đối. Nhờ đó, dù có dọn dẹp hay tạo lại stack đi chăng nữa, chúng mình cũng không bao giờ lo vô tình xóa mất Docker image của production, snapshot của database, hay secret của ứng dụng.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Sơ đồ luồng quyết định dọn dẹp của dự án awsplace:
- Xoá Stack (cdk destroy) → loại bỏ tài nguyên compute, network, và security
- Tài nguyên Được Giữ lại (chính sách RETAIN) → tồn tại sau khi xoá stack
- Huỷ Dữ liệu Thủ công (quy trình runbook) → yêu cầu phê duyệt bằng văn bản
Lưu tại: static/images/5.8/cleanup-decision-flow.png
-->
