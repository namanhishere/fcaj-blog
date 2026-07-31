---
title: "Deploy Frontend"
date: 2024-01-01
weight: 6
chapter: false
pre: " <b> 5.6. </b> "
---

## Deploy Frontend lên AWS Amplify

Frontend của **awsplace** là một ứng dụng HTML tĩnh, gọn nhẹ — không sử dụng framework JavaScript phức tạp như React hay Vue. Thay vào đó, việc deploy dựa vào một script build bằng shell thực hiện thay thế token, và quy trình CI/CD tải asset cuối cùng trực tiếp lên AWS Amplify. Toàn bộ quá trình được tự động hóa hoàn toàn.

### Phần 1: Hạ Tầng Ứng Dụng Amplify (Định nghĩa trong CDK)

Nền tảng cho việc deploy frontend là tài nguyên **AWS Amplify App**, được cung cấp bởi **AwsplaceStack** (như đã trình bày chi tiết ở phần trước). Mã CDK trong **cdk/lib/amplify.ts** cấu hình tài nguyên này với các hành vi quan trọng:

1. **Mô hình Deploy Thủ công:** Ứng dụng Amplify được cố ý cấu hình mà không kết nối đến Git repository. Comment trong code giải thích rõ: "Không có nhà cung cấp mã nguồn nào được đính kèm: **dist/** của frontend được deploy vào ứng dụng này dưới dạng tài sản **.zip** từ CI". Điều này tách rời frontend hosting khỏi bất kỳ nhà cung cấp source control cụ thể nào và cho phép pipeline CI/CD kiểm soát hoàn toàn nội dung và thời điểm deploy.

2. **Tên miền tùy chỉnh & TLS:** Stack ánh xạ root domain (ví dụ: **place.namanhishere.com**) đến nhánh **production**. Amplify xử lý việc cung cấp và tự động gia hạn chứng chỉ TLS công khai cho domain này — không cung cấp ACM certificate cho root. (Wildcard cert **\*.domain** chỉ được ALB và API Gateway sử dụng.)

3. **Luật Rewrite SPA:** Thay vì dùng SPA redirect mặc định, stack định nghĩa hai custom rule:
   - Rule đầu tiên sử dụng source pattern dạng regex, viết lại các path không có phần mở rộng thành **/index.html** — nhưng quan trọng là thêm **html** vào danh sách allowlist. Điều này đảm bảo request đến **/admin.html** được phục vụ đúng file thực tế, không bị viết lại thành SPA shell. Nếu thiếu rule này, trang admin dashboard sẽ bị hỏng.
   - Rule thứ hai là **404 rewrite** catch-all — mọi path không khớp rule đầu tiên hoặc file thực tế sẽ trả về **/index.html** với status 404, cho phép client-side router xử lý.

---

### Phần 2: Quy Trình Build (scripts/build-frontend.sh)

Quy trình build frontend được xử lý bởi **scripts/build-frontend.sh** — một công cụ tạo mẫu xây dựng bằng shell tiêu chuẩn.

**Cách hoạt động:**

- Script định nghĩa hàm **apply_tokens()** sử dụng **sed** để tìm và thay thế các placeholder token trong file HTML nguồn (**public/index.html** và **public/admin.html**). Các token bao gồm **{{BRAND_NAME}}**, **{{BRAND_DESCRIPTION}}**, **{{WS_URL}}**, **{{FRONTEND_API_URL}}**, và nhiều biến branding khác.

- Giá trị mặc định cho brand được hardcode trong script (ví dụ: **BRAND_NAME** mặc định là "lẩu/Place"), nhưng có thể được ghi đè qua file **.env** khi phát triển cục bộ hoặc qua biến môi trường CI/CD.

- Các endpoint production được tạo từ **DOMAIN_NAME**: WebSocket URL trở thành **wss://ws.{DOMAIN_NAME}/ws** và API URL trở thành **https://api.{DOMAIN_NAME}**.

**Đầu ra:** Script xử lý cả hai file HTML, copy tất cả static asset không phải HTML (CSS, hình ảnh, font) từ **public/** vào **dist/**, và kết thúc bằng bước xác minh — sử dụng **grep** để kiểm tra bất kỳ token **{{** nào còn sót. Nếu phát hiện placeholder chưa được giải quyết, build sẽ dừng ngay lập tức.

---

### Phần 3: Quy Trình Deploy trong CI/CD

Bước deploy trong pipeline CI/CD là script nhiều lệnh điều phối việc upload. Chi tiết từng bước:

1. **Lấy thông tin Amplify App:** Script truy vấn CloudFormation stack output bằng **aws cloudformation describe-stacks** để lấy **AmplifyAppId** và **AmplifyBranchName**. Điều này đảm bảo pipeline luôn nhắm đúng tài nguyên Amplify — kể cả khi stack được tạo lại.

2. **Đóng gói tài sản Frontend:** Thư mục **dist/** được nén thành file zip duy nhất (**amplify-dist.zip**). Đây là deployment artifact.

3. **Khởi tạo Deployment:** Script gọi **aws amplify create-deployment**, báo cho Amplify chuẩn bị cho đợt deploy thủ công mới. Amplify phản hồi với hai thông tin quan trọng:
   - Một **jobId** duy nhất để theo dõi đợt deploy.
   - Một **URL S3 đã ký sẵn (pre-signed)** — quyền truy cập tạm thời, an toàn để upload file zip trực tiếp lên S3 bucket do Amplify quản lý.

4. **Tải lên tài sản:** Script sử dụng **curl** để upload **amplify-dist.zip** lên pre-signed URL.

5. **Bắt đầu Job Deploy:** **aws amplify start-deployment** được gọi với **jobId**, báo hiệu Amplify bắt đầu xử lý file zip và deploy nội dung lên CDN toàn cầu.

6. **Chờ hoàn thành:** Script đi vào vòng lặp **while**, thăm dò trạng thái deploy mỗi 10 giây bằng **aws amplify get-job**. Nó kiểm tra trạng thái **SUCCEED** hoặc **FAILED**. Timeout 10 phút được đặt ra để ngăn job chạy vô thời hạn nếu có sự cố.

> ![Các Job Deploy trên Amplify](/images/5-Workshop/5.6-Deploy-Frontend/Screenshot%202026-07-27%20200851.png)

Khi deployment thành công, frontend đã live và được phân phối toàn cầu qua CDN của Amplify. Pipeline CI/CD tiếp tục sang bước tiếp theo — cập nhật ECS service và chạy kiểm tra sau deploy.