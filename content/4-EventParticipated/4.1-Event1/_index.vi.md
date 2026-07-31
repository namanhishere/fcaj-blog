---
title: "Event 1"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 4.1. </b> "
---

# Bài thu hoạch “FCAJ x Agentic AI Build Week”

### Mục Đích Của Sự Kiện

- Kết nối các bạn trẻ công nghệ với lãnh đạo AWS và chuyên gia trong lĩnh vực Agentic AI
- Khuyến khích người tham gia thách thức các cách làm việc truyền thống bằng kiến trúc AI
- Tạo sân chơi để các đội xây dựng và thuyết trình sản phẩm Agentic AI trong vòng 24 giờ
- Trình diễn ứng dụng thực tế của AWS Bedrock, AI agents và agentic workflows
- Thúc đẩy tinh thần hợp tác, tạo mẫu nhanh và giải quyết vấn đề theo hướng khởi nghiệp

### Danh Sách Diễn Giả

- **Lãnh đạo AWS** – Phát biểu khai mạc về tương lai của AI và kiến trúc agentic
- **Ban giám khảo Hackathon** – Các chuyên gia đánh giá dự án dựa trên tác động kinh doanh và chất lượng kỹ thuật

### Nội Dung Nổi Bật

#### One Team: Đặt món KFC bằng hội thoại (Giải Nhất)

- Ứng dụng fast-food truyền thống có độ ma sát cao — người dùng phải tải app, tạo tài khoản và thao tác qua menu phức tạp
- Xây dựng chatbot đa kênh trên Zalo và WhatsApp cho phép đặt món ăn một cách tự nhiên ngay trong ứng dụng chat
- Tận dụng AWS Bedrock và AI agent có bộ nhớ để xử lý ngôn ngữ tự nhiên, tiếp nhận các câu hỏi phụ và hoàn tất đơn hàng mà không cần rời khỏi giao diện chat

#### Signal Scout: Tình báo doanh nghiệp (Giải Nhì)

- Việc thu thập thông tin tình báo về cấu trúc doanh nghiệp của đối thủ và dự báo thành công của họ hiện đang rất thủ công và phân mảnh
- Phát triển công cụ AI dành cho bộ phận HR và chiến lược kinh doanh, sử dụng web scraping (Tiny Fish) và AWS Bedrock agents
- Thu thập dữ liệu phân mảnh về đối thủ (báo cáo tài chính, thay đổi cơ cấu công ty), tổng hợp và dự báo ROI cùng rủi ro nếu doanh nghiệp áp dụng các thay đổi cơ cấu đó

#### Team Plan: Kiến trúc sư giải pháp Cloud AI

- Các Cloud Solution Architect thường nhận yêu cầu gấp từ khách hàng để thiết kế kiến trúc và ước tính chi phí chỉ trong vài ngày hoặc vài giờ
- Xây dựng ứng dụng AI-native cho phép người dùng nhập yêu cầu bằng ngôn ngữ tự nhiên và tải lên chính sách công ty
- AI agent tự động vẽ sơ đồ kiến trúc AWS, tạo báo giá chi phí và viết script Terraform (Infrastructure as Code) để triển khai hạ tầng ngay lập tức

#### Team 3K: "Sheper" Giám sát đám đông

- Tình trạng ùn tắc và tắc nghẽn tại các không gian công cộng lớn như sân bay, siêu thị gây ảnh hưởng đến vận hành
- Xây dựng hệ thống computer vision thời gian thực sử dụng YOLO object detection, AWS Kinesis và Bedrock agents
- Giám sát luồng camera trực tiếp để phát hiện mật độ đám đông theo từng khu vực, với AI agent đóng vai trò co-pilot cho người vận hành — cảnh báo điểm nghẽn và đề xuất điều phối nhân sự

#### Six Pillar: Quy trình chống rửa tiền (AML)

- Các tổ chức tài chính phải xử lý số lượng lớn cảnh báo dương tính giả về rửa tiền, buộc nhân viên phân tích dành hàng giờ xem xét các giao dịch hợp lệ
- Phát triển Adaptive Workflow Engine sử dụng mô hình machine learning để phát hiện ban đầu nhanh chóng, sau đó kích hoạt ba AI sub-agent chuyên biệt: kiểm tra hồ sơ KYC, truy vết dòng tiền và đối chiếu danh sách trừng phạt
- Tổng hợp báo cáo bằng chứng và đưa ra quyết định ban đầu, chỉ chuyển tiếp những trường hợp mơ hồ nhất cho nhân viên phân tích

### Những Gì Học Được

#### Kiến Trúc Agentic AI

- Hiểu cách AI agents có bộ nhớ duy trì ngữ cảnh hội thoại cho các tương tác phức tạp nhiều lượt
- Học cách các sub-agent chuyên biệt (KYC, truy vết tiền, danh sách trừng phạt) phối hợp để giải quyết các nhiệm vụ điều tra phức tạp
- Nhận ra rằng AI agents hiệu quả nhất khi đóng vai trò co-pilot thay vì tự động ra quyết định trong các tình huống có rủi ro cao

#### Tư Duy Problem-First

- Các dự án thành công nhất đều tập trung vào một vấn đề thực tế rõ ràng thay vì phô diễn công nghệ phức tạp
- Giữ phạm vi nhỏ gọn và tập trung vào MVP là yếu tố then chốt để hoàn thành trong 24 giờ
- Ban giám khảo đánh giá cao tác động kinh doanh và sự thấu hiểu vấn đề hơn là độ phức tạp kỹ thuật

#### Làm Việc Nhóm và Tạo Mẫu Nhanh

- Các đội hiệu quả phân chia công việc rõ ràng: frontend, backend, AI và thuyết trình
- Bỏ qua cái tôi và hỗ trợ lẫn nhau dưới áp lực thời gian là yếu tố sống còn
- Tạo mẫu nhanh với AWS Bedrock và công cụ agentic giúp tăng tốc đáng kể quá trình phát triển

### Ứng Dụng Vào Công Việc

- Khám phá AWS Bedrock agents để xây dựng quy trình AI hội thoại và điều tra
- Áp dụng mô hình phối hợp sub-agent cho các quy trình kinh doanh phức tạp nhiều bước
- Sử dụng YOLO và AWS Kinesis cho các tình huống giám sát computer vision thời gian thực
- Áp dụng mô hình sinh Infrastructure as Code (Terraform) bằng AI để tăng tốc triển khai cloud
- Tích hợp tư duy "problem-first" vào các dự án tương lai: xác thực vấn đề trước khi thiết kế giải pháp

### Trải nghiệm trong event

Tham gia **FCAJ x Agentic AI Build Week** là một trải nghiệm căng thẳng nhưng đầy bổ ích, quy tụ những bạn trẻ công nghệ đầy tham vọng để xây dựng sản phẩm Agentic AI trong 24 giờ. Hackathon không chỉ thử thách kỹ năng kỹ thuật mà còn thúc đẩy chúng tôi suy nghĩ như những doanh nhân khởi nghiệp.

#### Học hỏi từ lãnh đạo AWS và ban giám khảo
- Các lãnh đạo AWS nhấn mạnh rằng AI không chỉ đơn thuần là tự động hóa công việc mà còn là tái định hình cách chúng ta làm việc và giải quyết vấn đề
- Ban giám khảo đưa ra những phản hồi sắc bén, mang tính xây dựng, giúp các đội hiểu điều gì làm cho một sản phẩm thực sự đáng đầu tư

#### Trải nghiệm thực tế với Agentic AI
- Quan sát năm cách ứng dụng agentic AI rất khác nhau — từ đặt món fast-food đến chống rửa tiền
- Hiểu rõ hơn cách AWS Bedrock, AI agents có bộ nhớ và điều phối sub-agent vận hành trong các prototype thực tế
- Học cách computer vision (YOLO) và dữ liệu streaming (Kinesis) tích hợp với AI agents để hỗ trợ ra quyết định thời gian thực

#### Phối hợp dưới áp lực
- Trải nghiệm động lực của một sprint xây dựng 24 giờ — phân chia vai trò, quản lý mệt mỏi và lặp nhanh
- Nhận ra rằng một bài demo được thuyết trình tốt với tuyên bố vấn đề rõ ràng có thể vượt trội hơn các giải pháp kỹ thuật phức tạp nhưng truyền đạt kém

#### Bài học rút ra
- Agentic AI mạnh mẽ nhất khi tăng cường khả năng ra quyết định của con người thay vì thay thế hoàn toàn
- Giữ phạm vi tinh gọn (MVP) và tập trung vào vấn đề của người dùng luôn là chiến lược chiến thắng
- Sự ăn ý trong nhóm và phân chia vai trò hiệu quả quan trọng không kém năng lực kỹ thuật trong môi trường áp lực cao

#### Một số hình ảnh khi tham gia sự kiện

![FCAJ x Agentic AI Build Week](/images/4-EventParticipated/4.1-Event1/Screenshot%20from%202026-07-25%2009-28-32.png)

![FCAJ x Agentic AI Build Week](/images/4-EventParticipated/4.1-Event1/image.png)

> Tổng thể, FCAJ x Agentic AI Build Week không chỉ là một cuộc thi — đó còn là một bài học chuyên sâu về cách xây dựng sản phẩm AI giải quyết vấn đề thực tế, một bài học về làm việc nhóm dưới áp lực, và một cái nhìn về tương lai của các kiến trúc agentic.
