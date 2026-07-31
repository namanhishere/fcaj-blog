---
title: "Xác thực Pipeline CI/CD"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 5.7.3. </b> "
---

Dự án awsplace vận hành song song hai CI/CD pipeline: **GitHub Actions** (.github/workflows/deploy.yml) và **GitLab CI** (.gitlab-ci.yml). Cả hai pipeline đóng vai trò "người gác cổng" tự động — không có code nào đến được production mà không vượt qua tất cả các giai đoạn xác thực.

#### Tổng quan pipeline

Workflow GitHub Actions được đặt tên **"Test & Deploy"** và được kích hoạt khi:
- Push vào **main** — chạy tất cả test VÀ triển khai
- Pull request vào **main** — chỉ chạy test (không triển khai)
- Push tag — chạy tất cả test VÀ triển khai

```yaml
on:
  push:
    branches: [main]
    tags: ['*']
  pull_request:
    branches: [main]
```

---

#### Kiến trúc cổng triển khai (Deployment Gate)

Job triển khai (deploy) có chuỗi phụ thuộc **needs** nghiêm ngặt — chỉ chạy sau khi TẤT CẢ các job test thành công:

```yaml
deploy:
  needs:
    [test-lambda, test-go-unit, test-go-postgres, test-go-ministack, test-cdk, publish-raftdb-image]
  if: github.ref == 'refs/heads/main'
```

Điều này có nghĩa là nếu bất kỳ job nào trong 6 job tiên quyết thất bại, việc triển khai sẽ bị chặn hoàn toàn.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Vào tab GitHub Actions và mở một workflow run.
Chụp sơ đồ phụ thuộc trực quan cho thấy deploy job phụ thuộc vào tất cả test job.
GitHub hiển thị đồ thị này dưới dạng biểu đồ luồng ngang.
Lưu tại: static/images/5.6/deployment-gate.png
-->

---

#### Các bước xác thực trước triển khai

Trước khi chạy cdk deploy, pipeline thực thi các script xác thực quan trọng:

#### 1. Xác thực biến môi trường

```bash
bash scripts/validate-deploy-env.sh
```

Script này (được test bởi deploy-config.test.cjs) đảm bảo:
- Tất cả secret bắt buộc đều có mặt và không rỗng
- Không có tham chiếu biến GitLab chưa được giải quyết bị rò rỉ vào môi trường
- Giá trị secret không bị in ra log

#### 2. Chuẩn bị CloudFormation Stack

```bash
bash scripts/prepare-cloudformation-deploy.sh AwsplaceStack
```

Script này xử lý các CloudFormation stack bị kẹt:
- **CREATE_COMPLETE** hoặc **UPDATE_COMPLETE** → tiến hành bình thường
- **ROLLBACK_FAILED** → tự động xoá stack lỗi và cho phép tạo mới
- **UPDATE_ROLLBACK_FAILED** → từ chối tự động xoá (cần can thiệp thủ công)

#### 3. Kiểm tra WebSocket Origin

```bash
bash scripts/check-websocket-origin.mjs
```

Cả pipeline GitHub và GitLab đều xác minh URL origin của WebSocket khớp với domain triển khai, ngăn ngừa lỗi CORS/origin mismatch.

---

#### Triển khai CDK

Sau khi tất cả bước xác thực hoàn tất, việc triển khai thực tế diễn ra:

```yaml
- name: CDK deploy
  env:
    SESSION_SECRET: ${{ secrets.SESSION_SECRET }}
    DISCORD_CLIENT_ID: ${{ secrets.DISCORD_CLIENT_ID }}
    HOSTED_ZONE_ID: ${{ secrets.HOSTED_ZONE_ID }}
    DOMAIN_NAME: ${{ secrets.DOMAIN_NAME }}
    ECS_IMAGE_TAG: ${{ github.sha }}
    RAFTDB_IMAGE_DIGEST: ${{ needs.publish-raftdb-image.outputs.digest }}
  run: |
    bash scripts/validate-deploy-env.sh
    bash scripts/prepare-cloudformation-deploy.sh AwsplaceStack
    cd cdk
    npm ci && npm run build
    npx cdk deploy --require-approval never --no-strict --all --import-existing-resources
```

Các flag quan trọng:
- **--require-approval never** — bỏ qua xác nhận thủ công (CI là tự động)
- **--import-existing-resources** — xử lý an toàn các tài nguyên đã tồn tại ngoài CDK
- **--all** — triển khai tất cả stack (AwsplaceStack + RaftDbStagingStack nếu bật)

---

#### Xác thực sau triển khai

Sau khi CDK triển khai hạ tầng, pipeline tiếp tục:

1. Push Docker image lên ECR sử dụng **scripts/push-ecs-image.sh**
2. Triển khai frontend lên Amplify qua asset upload
3. Chờ ECS service ổn định sử dụng **aws ecs wait services-stable**
4. Xác minh bản build frontend có đúng API và WebSocket endpoint từ domain

---

#### Chuỗi giám sát RaftDB Image (Chain of Custody)

RaftDB image tuân theo chuỗi giám sát nghiêm ngặt:

1. **Build** — docker build tạo image (không cần cloud credentials)
2. **Test** — 4 contract test xác thực hành vi image
3. **Scan** — Trivy quét lỗ hổng HIGH/CRITICAL
4. **Xuất bằng chứng** — Image ID và kết quả scan được lưu thành artifact
5. **Publish** — Sau khi scan pass, push lên ECR với tag bất biến
6. **Verify** — Sau khi push ECR, pull lại image và chạy lại contract test để xác nhận tính toàn vẹn
7. **Lưu trữ** — Bằng chứng publication được upload với thời hạn lưu trữ 90 ngày

```yaml
# Xác minh lại sau khi publish lên ECR
- name: Pull digest vào image cache sạch
  run: |
    docker pull "${ECR_URI}@${IMAGE_DIGEST}"
    bash raftdb/test/container_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
    bash raftdb/test/migration_runtime_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
```

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Mở một workflow run "Test & Deploy" thành công trong GitHub Actions.
Mở rộng job "deploy" và chụp các step hiển thị validate, prepare, và CDK deploy.
Lưu tại: static/images/5.6/deploy-steps.png

Gợi ý chụp ảnh 2: Mở job "raftdb-image" và chụp chuỗi các step:
Build → Contract tests → Trivy scan → Export evidence
Lưu tại: static/images/5.6/raftdb-image-chain.png
-->

---

#### Tích hợp GitLab CI

File **.gitlab-ci.yml** (26,685 byte) phản chiếu workflow GitHub Actions với các giai đoạn xác thực tương đương. Các bài deployment contract test (deployment-contract.test.cjs) xác minh rõ ràng rằng cả hai pipeline đều chứa cùng các lệnh quan trọng:

```javascript
test('GitLab and GitHub publish and deploy through the shared ECR contract', () => {
  for (const workflow of [gitlab, github]) {
    expect(workflow).toContain('scripts/push-ecs-image.sh');
    expect(workflow).toContain('ECS_IMAGE_TAG');
    expect(workflow).toContain('aws ecs wait services-stable');
    expect(workflow).toContain('--import-existing-resources');
  }
});
```

Cách tiếp cận "test-the-test" này đảm bảo hai hệ thống CI không bao giờ bị lệch nhau.
