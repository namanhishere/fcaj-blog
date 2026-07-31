---
title: "Kiểm thử Hạ tầng CDK"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.7.1. </b> "
---

Mã nguồn CDK của awsplace chứa **7 file test** bên trong thư mục **cdk/**, tất cả đều sử dụng Jest làm test runner. Các bài test này không mock CDK construct, mà gọi **cdk synth** để tạo ra CloudFormation template thực và phân tích file JSON đầu ra để xác thực tính đúng đắn của hạ tầng.

#### Tổng quan các file test

| File Test | Mục đích | Các assertion chính |
|---|---|---|
| deployment-contract.test.cjs | Xác thực hợp đồng triển khai giữa CDK và CI/CD pipeline | Tên ECR repository, ECS image tag, cấu hình circuit breaker, CloudFormation exports |
| deploy-config.test.cjs | Test các helper script validate-deploy-env.sh và prepare-cloudformation-deploy.sh | Xác thực biến môi trường, xử lý trạng thái stack |
| raftdb.test.cjs | Xác thực toàn diện RaftDB staging stack | Cô lập VPC, ECS task definition, security group, mã hóa EFS, cấu hình S3 snapshot |
| raftdb-workflow.test.cjs | Test các file workflow CI/CD theo yêu cầu RaftDB | Các bước build Docker, quét image, qualification test |
| raftdb-runbook.test.cjs | Xác thực tài liệu runbook vận hành so với mã nguồn | Lệnh runbook khớp với hạ tầng thực |
| raftdb-application-modes.test.cjs | Test máy trạng thái application mode | Các chuyển đổi DATA_MODE, retry contract, tài liệu protocol |
| amplify.test.cjs | Xác thực frontend hosting sử dụng Amplify (không phải CloudFront) | Tài nguyên Amplify App/Branch/Domain tồn tại, không có tài nguyên CloudFront |

---

#### 1. Kiểm thử hợp đồng triển khai (Deployment Contract Testing)

File: **deployment-contract.test.cjs** 

Đây là file test quan trọng nhất. Nó xác thực một hợp đồng chung giữa mã hạ tầng CDK và các CI/CD pipeline. Ý tưởng là: cả GitHub Actions và GitLab CI đều phụ thuộc vào các CloudFormation output và thuộc tính tài nguyên cụ thể. Nếu mã CDK thay đổi những thứ này, việc triển khai sẽ bị hỏng. Bài test này sẽ phát hiện những thay đổi gây lỗi đó.

Các test case chính:

#### a) Ổn định ECR Repository

```javascript
test('application ECR repository has a stable retained physical name', () => {
  const repositories = resourcesByType(defaultTemplate, 'AWS::ECR::Repository');
  expect(repositories).toHaveLength(1);
  expect(repository.Properties).toEqual(expect.objectContaining({
    RepositoryName: 'awsplace-ecs',
    ImageScanningConfiguration: { ScanOnPush: true },
    ImageTagMutability: 'MUTABLE_WITH_EXCLUSION',
  }));
  expect(repository.DeletionPolicy).toBe('Retain');
});
```

Bài test này đảm bảo:
- Có đúng **một** ECR repository tên **awsplace-ecs**.
- Repository bật **ScanOnPush** (tuân thủ bảo mật).
- DeletionPolicy là **Retain** — ngăn chặn việc xoá nhầm image production.
- Các image tag có tiền tố **raftdb-*** là bất biến (immutable — không thể ghi đè).

#### b) Cấu hình triển khai ECS

```javascript
test('ECS uses the requested image tag and exports exact deployment targets', () => {
  // ... synthesize với ECS_IMAGE_TAG=0123456789abcdef...
  expect(services[0][1].Properties.DeploymentConfiguration).toEqual(
    expect.objectContaining({
      DeploymentCircuitBreaker: { Enable: true, Rollback: true },
      MinimumHealthyPercent: 0,
      MaximumPercent: 100,
    })
  );
  expect(template.Outputs.EcsClusterName).toBeDefined();
  expect(template.Outputs.EcsServiceName).toBeDefined();
});
```

Bài test xác thực:
- ECS service sử dụng **deployment circuit breaker** với rollback tự động.
- CloudFormation export tên cluster và service (các script CI/CD phụ thuộc vào chúng để chạy lệnh **aws ecs wait services-stable**).

#### c) Từ chối input không hợp lệ

```javascript
test('invalid ECS image tags fail synthesis before deployment', () => {
  const { result } = synthWithImageTag('invalid/tag');
  expect(result.status).not.toBe(0);
  expect(`${result.stdout}\n${result.stderr}`).toContain(
    'ECS_IMAGE_TAG must be a valid Docker image tag'
  );
});
```

Đây là "negative test" — đảm bảo mã CDK dừng ngay với thông báo lỗi rõ ràng nếu định dạng image tag không hợp lệ, ngăn chặn các đợt triển khai sai.

#### d) Hợp đồng CORS Frontend-Backend

```javascript
test('ECS allows the browser origin derived from the deployed frontend domain', () => {
  // Synth với DOMAIN_NAME=canvas.example.com
  expect(environment.ALLOWED_ORIGINS).toBe('https://canvas.example.com');
});
```

Đảm bảo biến môi trường **ALLOWED_ORIGINS** của backend tự động khớp với domain frontend — để CORS không bị hỏng trên production.

#### e) Hợp đồng script CI/CD

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

Test này đọc trực tiếp file **.gitlab-ci.yml** và **deploy.yml** thực tế và assert rằng cả hai sử dụng cùng deployment script và pattern. Điều này ngăn không cho một hệ thống CI bị lệch (drift) so với hệ thống kia.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Chạy lệnh npm test trong thư mục awsplace/cdk.
Chụp đầu ra Jest hiển thị tất cả 7 file test pass với dấu tick xanh.
Lưu tại: static/images/5.6/cdk-test-results.png
-->

---

#### 2. Kiểm thử cấu hình triển khai (Deploy Configuration Testing)

File: **deploy-config.test.cjs** 

File này test các deployment helper script trong thư mục **scripts/** — cụ thể là **validate-deploy-env.sh** và **prepare-cloudformation-deploy.sh**.

Các kịch bản được test:

| Test Case | Nội dung xác thực |
|---|---|
| Chấp nhận cấu hình đã giải quyết | Tất cả env var bắt buộc (HOSTED_ZONE_ID, DOMAIN_NAME, SESSION_SECRET,...) đều có mặt |
| Từ chối biến GitLab chưa giải quyết | Bắt giá trị literal mà GitLab chưa interpolate |
| Từ chối secret thiếu | Fail nếu DISCORD_CLIENT_SECRET rỗng |
| Stack preparer: stack khoẻ mạnh | Giữ nguyên stack CREATE_COMPLETE |
| Stack preparer: rollback thất bại | Xoá stack ROLLBACK_FAILED và chờ dọn dẹp |
| Stack preparer: stack mới | Cho phép tạo khi stack chưa tồn tại |
| Stack preparer: update thất bại | Từ chối tự động xoá stack UPDATE_ROLLBACK_FAILED (cần can thiệp thủ công) |

Các bài test deploy-config sử dụng mock AWS CLI script để mô phỏng các trạng thái CloudFormation stack mà không cần AWS credentials thật.

---

#### 3. Xác thực hạ tầng RaftDB

File: **raftdb.test.cjs** 
Đây là file test lớn nhất. Nó xác thực toàn bộ **RaftDbStagingStack** — một CDK stack riêng biệt được dùng chuyên để diễn tập các thao tác Raft consensus trên hạ tầng dùng một lần.

Bài test tổng hợp template với nhiều cấu hình:
- Mặc định (RaftDB bị tắt)
- Bật (ENABLE_RAFTDB=true, RAFTDB_NODE_COUNT=3)
- Chế độ khôi phục (RAFTDB_RESTORE_FROM_S3=true)
- Sau khôi phục (RAFTDB_RESTORE_FROM_S3=false, với nhãn data generation)

Các khu vực được xác thực: cô lập VPC (VPC riêng biệt với production), 3 ECS task definition cho các member, quy tắc security group, volume EFS được mã hoá, và cấu hình S3 snapshot.

---

#### 4. Kiểm thử frontend hosting với Amplify

File: **amplify.test.cjs** 
Bài test ngắn gọn nhưng quan trọng, xác thực quyết định kiến trúc hosting frontend trên AWS Amplify thay vì CloudFront:

```javascript
test('the application stack hosts the frontend on Amplify, not CloudFront', () => {
  expect(resourcesByType(defaultTemplate, 'AWS::CloudFront::Distribution')).toHaveLength(0);
  expect(resourcesByType(defaultTemplate, 'AWS::Amplify::App').length).toBeGreaterThanOrEqual(1);
  expect(resourcesByType(defaultTemplate, 'AWS::Amplify::Branch').length).toBeGreaterThanOrEqual(1);
});
```

---

#### Chạy CDK test ở local

```bash
cd awsplace/cdk
npm install
npm test
```

Script **npm test** thực hiện tuần tự ba bước:
1. **npm run build** — Biên dịch TypeScript sang JavaScript thông qua tsc
2. **npm run synth** — Chạy cdk synth để tạo CloudFormation template
3. **jest --runInBand** — Chạy toàn bộ 7 file test tuần tự

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Chạy lệnh npm test trong thư mục awsplace/cdk và chụp đầu ra terminal hiển thị:
1. Phần biên dịch TypeScript
2. Đầu ra CDK synth
3. Kết quả Jest test (tất cả pass)
Lưu tại: static/images/5.6/npm-test-output.png
-->
