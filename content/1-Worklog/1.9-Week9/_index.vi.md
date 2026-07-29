---
title: "Worklog Tuần 9"
date: 2026-08-10
weight: 9
chapter: false
pre: " <b> 1.9. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 9:

* Viết báo cáo thực tập dưới dạng một site song ngữ có thể build ra PDF, thay vì một tài liệu ghép tay vào phút cuối.
* Hoàn tất bộ sơ đồ để mọi khẳng định về kiến trúc trong báo cáo đều có một hình được sinh ra từ tệp nguồn được commit kèm theo.
* Rà soát chi phí thực tế của bản triển khai, và bàn giao một danh sách viết rõ những gì đã xong và những gì chưa.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Dựng báo cáo thành một site Hugo song ngữ, mỗi trang gồm một tệp tiếng Anh cùng một bản sinh đôi tiếng Việt mang cùng weight và pre <br> - **Nối đường sinh PDF thay vì viết LaTeX bằng tay:** <br>&emsp; + scripts/convert_hugo_to_latex.py đi qua content/ và sinh một tệp .tex cho mỗi trang ở từng ngôn ngữ <br>&emsp; + các trang worklog đặt reportType worklog nên bảng công việc trở thành longtable <br>&emsp; + reportTableColumns thu bảng năm cột trên web xuống ba cột trong PDF <br> - Viết worklog cho tuần 1 đến tuần 9, các phần đề xuất, và các bài workshop bằng cả hai ngôn ngữ | 10/08/2026 | 10/08/2026 | <https://gohugo.io/content-management/multilingual/> <br> <https://gohugo.io/content-management/front-matter/> |
| 3   | - Hoàn tất bộ PlantUML: 22 tệp nguồn trong graph/src, mỗi sơ đồ có một bản sinh đôi tiếng Việt, render ra PNG và SVG rồi commit dưới static/images/diagrams thành 44 tệp <br> - Dùng PNG trên mọi trang đi vào PDF, vì pdflatex không đọc được SVG <br> - **Rà soát bằng chứng chi phí thay vì phỏng đoán:** <br>&emsp; + Cost Explorer có trả lời, nên bảng theo dịch vụ mang nhãn ACTUAL (Cost Explorer) <br>&emsp; + mọi dòng đo được đều dưới một xu mỗi tháng, nên đó không phải mức chi hằng tháng và không được trình bày như vậy <br>&emsp; + giá niêm yết được dẫn riêng cho bất cứ con số mang hình dạng chi phí hằng tháng | 11/08/2026 | 11/08/2026 | <https://plantuml.com/> <br> <https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html> |
| 4   | - Ghi lại quyết định chi phí mang tính cấu trúc lớn nhất kèm phép tính: natGateways là 0, nên với giá niêm yết ap-southeast-1 là 0.059 mỗi gateway-giờ, phần chi phí cố định tránh được là 43.07 USD mỗi tháng cho một gateway, hoặc 86.14 USD cho hai gateway mà maxAzs 2 sẽ cấp phát theo mặc định <br> - **Viết rõ phần việc còn lại thay vì để ngầm hiểu:** <br>&emsp; + production không có alarm CloudWatch nào; namespace RaftDb đã được cấp phát nhưng đang ngủ <br>&emsp; + production chỉ có một voter RaftDB, nên hôm nay chưa có dự phòng nhân bản <br>&emsp; + mỗi lần triển khai là một lần ngưng toàn phần ngắn, vì một tiến trình ghi sở hữu WAL trên EFS <br> - Bàn giao site báo cáo, các tệp nguồn sơ đồ và các tệp bằng chứng | 12/08/2026 | 12/08/2026 | <https://aws.amazon.com/vpc/pricing/> <br> <https://calculator.aws/> |

PDF được sinh từ chính phần markdown mà site render, nên front matter là thứ điều khiển báo cáo:

```yaml
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
```

Tệp nguồn sơ đồ được biên dịch ra cả hai định dạng và kết quả được commit, vì site đã publish và PDF cần hai định dạng khác nhau:

```bash
./graph/compile.sh
cp graph/output/*.png graph/output/*.svg static/images/diagrams/
```

### Kết quả đạt được tuần 9:

* Báo cáo là một site chứ không phải một tài liệu. Mọi trang tồn tại hai lần, một lần là `_index.md` và một lần là `_index.vi.md`, với cùng `weight` và `pre` để hai thanh điều hướng trùng khớp, và `python3 scripts/convert_hugo_to_latex.py` biến toàn bộ cây nội dung thành LaTeX cho một PDF tiếng Anh và một PDF tiếng Việt. Chín tuần worklog dùng bộ render worklog, thứ chuyển bảng công việc năm cột trong markdown thành `longtable` và chỉ giữ ba cột được nêu trong `reportTableColumns`. Viết theo cách này nghĩa là mọi dữ kiện trong báo cáo là một trang tôi có thể sửa rồi build lại, không phải một đoạn dán vào mẫu.

* Bộ sơ đồ đã đủ và tái lập được: 22 tệp nguồn PlantUML trong `graph/src/`, mỗi sơ đồ có một bản sinh đôi tiếng Việt, render ra cả PNG và SVG rồi commit thành 44 tệp dưới `static/images/diagrams/`. Các trang đi vào PDF tham chiếu PNG, vì `pdflatex` không đọc được SVG. Giá trị của việc commit bản render cạnh tệp nguồn là: người đọc không có toolchain Docker vẫn thấy được sơ đồ, còn người có thì sinh lại và so sánh được.

* Phần rà soát chi phí là số đo được, và nhỏ đến mức việc báo cáo trung thực quan trọng hơn việc báo cáo cho đẹp. Cost Explorer trả về dữ liệu, nên bảng theo dịch vụ mang nhãn `ACTUAL (Cost Explorer)` cho kỳ tháng Sáu và cho kỳ tháng Bảy chưa trọn mà chính API đánh dấu là ước lượng. Từng dòng đo được đều dưới một xu mỗi tháng. Đó là một con số thật và đồng thời không phải mức chi hằng tháng của kiến trúc này, nên bất cứ con số mang hình dạng chi phí hằng tháng trong báo cáo đều được dẫn từ giá niêm yết AWS, có kèm phép tính và có nhãn là giá niêm yết.

* Quyết định chi phí lớn nhất mang tính cấu trúc hơn là vận hành. VPC được dựng với `natGateways: 0` và các subnet public, còn task Fargate ra Internet bằng public IP của chính nó. Với giá niêm yết `ap-southeast-1` là 0.059 USD mỗi NAT-Gateway-giờ, điều đó tránh được 43.07 USD mỗi tháng cho một gateway, hoặc 86.14 USD mỗi tháng cho hai gateway mà CDK sẽ cấp phát theo mặc định với `maxAzs: 2`. Phí xử lý dữ liệu sẽ là phần cộng thêm và không được định lượng ở đây, vì chưa từng có gateway nào tồn tại nên không có số byte nào để nhân.

* Phần bàn giao nêu tên các khoảng trống chứ không nêu tính năng. Production chạy một voter RaftDB, nên hôm nay chưa có dự phòng nhân bản và mục tiêu ba voter đã ghi trong tài liệu chỉ tồn tại trong bộ tạo stack staging. Production không có alarm CloudWatch nào, và namespace tuỳ chỉnh `RaftDb` mà dashboard dựa trên đã được cấp phát nhưng đang ngủ cho tới khi runtime phát số liệu, nên không có lịch sử metric nào để bàn giao. Mỗi lần triển khai đưa canvas offline trong suốt thời gian triển khai, một cách có chủ ý, vì một tiến trình ghi sở hữu write-ahead log trên EFS. Cooldown khi đặt pixel được giữ trong bộ nhớ của tiến trình Go và mất khi khởi động lại. Giao thức RaftDB không có lớp xác thực, và đó là lý do sidecar chỉ tới được qua loopback.

* Có hai điều về chính bản báo cáo thuộc về phần bàn giao, vì người đọc sẽ nhận ra chúng. Kỳ thực tập kéo dài chín tuần, từ 15/06/2026 đến 12/08/2026, còn mẫu worklog của chương trình được viết cho mười hai tuần, nên cách quy đổi được nêu trong phần tiến độ thay vì kéo dãn cho đủ. Và báo cáo bao gồm worklog, bản đề xuất, các bài blog và workshop; những phần còn lại của mẫu chưa được viết, và trang gốc nói rõ điều đó thay vì liên kết tới những trang không tồn tại.
