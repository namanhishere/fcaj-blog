---
title: "Tự đánh giá"
date: 2026-07-31
weight: 6
chapter: false
pre: " <b> 6. </b> "
includeInReport: false
---

Trong suốt thời gian thực tập tại **Công ty TNHH Amazon Web Services Việt Nam** từ **15/06/2026** đến **12/08/2026** trong chương trình First Cloud AI Journey (FCAJ) Workforce Bootcamp, tôi đã có cơ hội học hỏi, rèn luyện và áp dụng kiến thức đã được trang bị tại trường vào môi trường làm việc thực tế.

Tôi đã dành toàn bộ chín tuần cho một dự án duy nhất: **awsplace**, một bảng vẽ pixel cộng tác thời gian thực được triển khai trên AWS. Hệ thống bao gồm một máy chủ WebSocket viết bằng Go, một engine lưu trữ Raft-consensus viết bằng C++23 (RaftDB), xác thực Discord OAuth2 thông qua AWS Lambda, hạ tầng được định nghĩa hoàn toàn bằng CDK TypeScript, và một pipeline CI/CD triển khai bằng thông tin xác thực OIDC không lưu trữ access key. Qua dự án này, tôi đã cải thiện kỹ năng lập trình hệ thống (Go, C++23), hạ tầng đám mây (AWS CDK, ECS Fargate, Lambda, API Gateway, EFS, S3, Secrets Manager), hệ thống phân tán (Raft consensus, write-ahead logging, snapshotting), và DevOps (GitLab CI, Trivy image scanning, OIDC federation).

Về tác phong, tôi duy trì nhật ký công việc hàng ngày, hoàn thành mọi đầu việc đã lên kế hoạch trong tuần quy định, viết test song song với code, và ghi lại các quyết định kiến trúc dưới dạng comment trong source code thay vì trong tài liệu riêng. Tôi tuân thủ cấu trúc chương trình đồng thời điều chỉnh mẫu worklog mười hai tuần cho kỳ thực tập chín tuần mà không thêm nội dung cho những tuần không làm việc.

Để phản ánh một cách khách quan quá trình thực tập, tôi xin tự đánh giá bản thân dựa trên các tiêu chí dưới đây:

| STT | Tiêu chí                            | Mô tả                                                                                            | Tốt | Khá | Trung bình |
| --- | ----------------------------------- | ------------------------------------------------------------------------------------------------ | --- | --- | ---------- |
| 1   | **Kiến thức và kỹ năng chuyên môn** | Hiểu biết về kiến trúc đám mây, áp dụng lý thuyết hệ thống phân tán vào thực tế, thành thạo Go, C++, TypeScript và các công cụ AWS, chất lượng công việc | ☐   | ✅   | ☐          |
| 2   | **Khả năng học hỏi**                | Tự nghiên cứu Raft consensus, hệ thống build C++23, CDK và OIDC federation từ nền tảng cơ bản    | ✅   | ☐   | ☐          |
| 3   | **Chủ động**                        | Thiết kế định dạng canvas trước khi viết server, xác định ràng buộc nibble parity trên bốn ngôn ngữ, viết test harness để kiểm chứng | ✅   | ☐   | ☐          |
| 4   | **Tinh thần trách nhiệm**           | Hoàn thành chín tuần công việc đúng kế hoạch, ghi lại mọi trade-off kiến trúc trong code, thừa nhận các điểm còn thiếu trong bàn giao cuối kỳ | ✅   | ☐   | ☐          |
| 5   | **Kỷ luật**                         | Duy trì cấu trúc nhật ký công việc hàng ngày, commit code với thông điệp rõ ràng, giữ lịch sử Git sạch sẽ | ✅   | ☐   | ☐          |
| 6   | **Tính cầu tiến**                   | Chấp nhận rằng production chỉ chạy một RaftDB voter thay vì giả vờ có cluster, ghi nhận rằng CloudWatch namespace được provision nhưng dormant, liệt kê các gap thay vì che giấu | ✅   | ☐   | ☐          |
| 7   | **Giao tiếp**                       | Viết báo cáo song ngữ dưới dạng website với sơ đồ biên dịch từ PlantUML, giải thích lý do đằng sau mỗi quyết định kiến trúc trong phần Proposal | ☐   | ✅   | ☐          |
| 8   | **Hợp tác nhóm**                    | Làm việc với mentor và đội ngũ admin FCAJ trong suốt kỳ thực tập, phối hợp với AWS Study Group để đăng bài blog | ☐   | ✅   | ☐          |
| 9   | **Ứng xử chuyên nghiệp**            | Tôn trọng đồng nghiệp và cấu trúc chương trình, coi kỳ thực tập là cơ hội học tập thực sự thay vì chỉ là một yêu cầu để hoàn thành | ✅   | ☐   | ☐          |
| 10  | **Tư duy giải quyết vấn đề**        | Gỡ lỗi Raft log corruption trên Go, C++ và JavaScript; giải quyết ràng buộc ECS `minHealthyPercent: 0` cho single-writer WAL; thiết kế nibble encoding byte-identical trên bốn ngôn ngữ | ☐   | ✅   | ☐          |
| 11  | **Đóng góp vào dự án/tổ chức**      | Bàn giao một hệ thống hoàn chỉnh và tái tạo được: một lệnh `cdk deploy` tạo ra toàn bộ tài nguyên AWS, RaftDB store sống sót qua các lần restart task, và trang web hoạt động tại `place.namanhishere.com` | ✅   | ☐   | ☐          |
| 12  | **Tổng thể**                        | Hoàn thành một ứng dụng full-stack với hạ tầng dưới dạng code, một storage engine tự viết, và CI/CD tự động, đồng thời trung thực ghi nhận những phần việc còn dang dở | ✅   | ☐   | ☐          |

### Cần cải thiện

* Nâng cao nhận thức về vận hành: production không có CloudWatch alarm nào, và RaftDB custom namespace được provision nhưng dormant vì chưa có publisher trong source tree. Lẽ ra tôi nên ưu tiên ít nhất một alarm cơ bản về trạng thái task trước khi tuyên bố dự án hoàn thành.

* Lên kế hoạch dự phòng ngay từ đầu: chiến lược triển khai có chủ đích chỉ chạy một RaftDB voter vì một writer duy nhất sở hữu EFS write-ahead log. Mục tiêu cluster ba voter đã được ghi nhận trong tài liệu nhưng chưa từng lên production. Các dự án sau nên tích hợp replication sớm hơn thay vì trì hoãn sang giai đoạn sau.

* Thiết kế cho suy giảm chức năng một cách có kiểm soát (graceful degradation): khi RaftDB sidecar gặp sự cố giữa chừng ở chế độ `raftdb-only`, hành vi của ứng dụng chưa được ghi nhận trong tài liệu. Mọi nhánh lỗi cần được suy nghĩ thấu đáo và mô tả trước khi code được phát hành.

* Cải thiện giao tiếp kỹ thuật: mặc dù báo cáo đầy đủ và code được comment kỹ lưỡng, tôi có thể đã cập nhật bằng lời cho mentor thường xuyên hơn thay vì chỉ dựa vào worklog như kênh giao tiếp chính.
