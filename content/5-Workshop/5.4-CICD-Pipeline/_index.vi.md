---
title: "CI/CD Pipeline"
date: 2024-01-01
weight: 4
chapter: false
pre: " <b> 5.4. </b> "
---

## CI/CD Pipeline

awsplace sử dụng kiến trúc **dual CI** — GitHub Actions đóng vai trò nền tảng CI/CD chính, còn GitLab CI hoạt động như bản mirror đồng bộ. Cả hai pipeline đều chia sẻ cùng các stage, cùng các script hỗ trợ, và quan trọng nhất — cùng một chiến lược bảo mật. Không có nền tảng nào lưu trữ AWS credential dài hạn. Mỗi lần pipeline chạy, hệ thống sẽ trao đổi token qua **OIDC** (OpenID Connect) để nhận credential tạm thời từ AWS, tự động hết hạn sau một giờ.

Sơ đồ dưới đây minh họa toàn bộ vòng đời từ thời điểm developer chạy lệnh **git push** cho đến khi deployment được xác minh thành công trên production.

![Kiến trúc CI/CD Pipeline](/images/5-Workshop/5.4-CICD-Pipeline/cicd-pipeline.png)

> **Thực thi Pipeline thực tế:** Dưới đây là giao diện thực thi pipeline trên GitLab CI với tất cả 14 job hoàn thành thành công qua 4 stage chính (**build-ci-image**, **test**, **build**, **deploy**).

![Giao diện thực thi GitLab CI Pipeline](/images/5-Workshop/5.4-CICD-Pipeline/98e24f05-f52d-4bcb-a308-0133be4483b0.jpg)

---

### 1. Code Commit và CI Triggers

Pipeline được kích hoạt khi developer đẩy code lên repository:

| Sự kiện | GitHub Actions | GitLab CI |
|---------|---------------|-----------|
| Push lên **main** | Chạy toàn bộ pipeline (test, build, deploy) | Tương tự |
| Pull Request / Merge Request | Chỉ chạy stage test | Chỉ chạy stage test |
| Push tag | Build + đẩy lên GHCR + tạo GitHub Release | Build + tạo GitLab Release |

GitHub là repository chính. Một cơ chế mirror sync đẩy commit sang GitLab instance tự host tại **git.namanhishere.com**, nơi pipeline GitLab CI được kích hoạt độc lập.

Riêng component RaftDB (viết bằng C++) có một workflow riêng biệt (**raftdb-ci.yml**). Workflow này chỉ chạy khi có thay đổi trong thư mục **raftdb/** và thực hiện bốn lane sanitizer (ASan, UBSan, TSan, Release) cùng một bài test libFuzzer smoke. GitHub Actions là nguồn chính thức cho workflow này — GitLab CI mirror lại để đảm bảo tương đồng.

---

### 2. OIDC Authentication — Không Sử Dụng Static Credentials

Cả hai nền tảng CI đều xác thực với AWS thông qua **OIDC federation** thay vì lưu trữ IAM access key dưới dạng secret. Quy trình hoạt động như sau:

1. Nền tảng CI tạo ra một JWT token có chữ ký xác định pipeline run, repository, và branch hiện tại.
2. Token này được trao đổi với AWS STS qua **AssumeRoleWithWebIdentity** để nhận credential tạm thời — gồm access key, secret key, và session token.
3. Credential tạm thời này hết hạn sau một giờ. Không có bất kỳ key dài hạn nào tồn tại trong cấu hình CI.

**GitHub Actions** sử dụng action chính thức **aws-actions/configure-aws-credentials@v4**:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ap-southeast-1
```

**GitLab CI** sử dụng cơ chế **id_tokens** tích hợp sẵn:

```yaml
id_tokens:
  AWS_JWT_TOKEN:
    aud: https://git.namanhishere.com
```

Sau đó token được trao đổi thủ công qua AWS CLI:

```bash
ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity \
  --role-arn ${AWS_ROLE_ARN} \
  --role-session-name "GitLabCI-${CI_PIPELINE_ID}" \
  --web-identity-token ${AWS_JWT_TOKEN} \
  --duration-seconds 3600 \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $3}')
```

Cả hai nền tảng đều assume cùng một IAM role (**AWS_ROLE_ARN**). Trust policy của role này giới hạn OIDC provider và repository nào được phép assume.

Đây là best practice về bảo mật được khuyến nghị bởi cả AWS và GitHub — hoàn toàn không có AWS credential tĩnh nào được lưu trong secret store của bất kỳ nền tảng CI nào.

> **Cấu hình AWS IAM OIDC Provider:** OpenID Connect identity provider được cấu hình trong AWS IAM cho **git.namanhishere.com**:

![Cấu hình AWS IAM OpenID Connect Provider](/images/5-Workshop/5.4-CICD-Pipeline/31fe64fd-ac46-44c4-bbe9-2ec0d4945367.jpg)

> **Biến CI/CD Variables (Protected & Masked):** Các thông số cấu hình ứng dụng và **AWS_ROLE_ARN** được bảo mật dưới dạng các biến protected và masked trên GitLab CI:

![Cấu hình các biến CI/CD Variables trên GitLab](/images/5-Workshop/5.4-CICD-Pipeline/844cf6a4-2878-463d-b334-f46543ba1a63.jpg)

---

### 3. Test Stage — Ma Trận Test Toàn Diện

Tất cả các bài test chạy song song trong stage test. Pipeline yêu cầu mọi job test phải pass trước khi chuyển sang build hoặc deploy. Dưới đây là toàn bộ ma trận test:

#### Lambda Tests (Node.js)

| Job | Runtime | Nội dung test |
|-----|---------|--------------|
| **test-lambda** | Node.js 24 | Unit test bằng Vitest cho Lambda xác thực (46 test case) + kiểm tra nibble-parity giữa hai ngôn ngữ |

Bài test **nibble-parity** cần được lưu ý đặc biệt — nó xác minh rằng Lambda (Node.js) và Go ECS server tạo ra kết quả encoding canvas giống nhau từng byte. Do cả hai runtime cùng ghi vào chung DynamoDB table và S3 bucket, chỉ cần một sai lệch nhỏ trong encoding là có thể làm hỏng toàn bộ canvas.

#### Go Server Tests

| Job | Runtime | Service phụ thuộc | Nội dung test |
|-----|---------|-------------------|--------------|
| **test-go-unit** | Go 1.25 | Không | Canvas logic, auth middleware, WebSocket handler — unit test thuần, không phụ thuộc bên ngoài |
| **test-go-postgres** | Go 1.25 | PostgreSQL 16 | Kiểm tra conformance backend PostgreSQL + filesystem store |
| **test-go-ministack** | Go 1.25 | MiniStack (giả lập DynamoDB + S3) | DynamoDB backend, S3 storage, admin API, scheduler, full E2E integration test |

Job MiniStack là job kiểm tra kỹ lưỡng nhất — nó khởi động một AWS emulator cục bộ, tạo DynamoDB table và S3 bucket thông qua **scripts/start-ministack.sh**, rồi chạy các integration test end-to-end đi qua đúng code path mà production sử dụng.

#### CDK Infrastructure Tests

| Job | Runtime | Nội dung test |
|-----|---------|--------------|
| **test-cdk** | Node.js 24 | TypeScript compilation, CDK synthesis qua **cdk synth**, RaftDB workflow test, deploy config contract test, deployment contract test |

Các bài test này synthesize CloudFormation template mà không thực sự deploy. Chúng phát hiện các lỗi cấu hình (sai resource property, thiếu output, sai thứ tự dependency) trước khi thực hiện deployment thật.

#### RaftDB Tests

| Job | Runtime | Nội dung test |
|-----|---------|--------------|
| **raftdb-image** | Docker 27 | Build Docker image RaftDB, chạy container contract test, qualification test, migration test, S3 backup/restore test, và quét lỗ hổng bảo mật bằng Trivy |
| **test-raftdb-fuzz** | Clang 19 | libFuzzer smoke test trên TCP frame parser (300 giây) |

Job **raftdb-image** đặc biệt quan trọng về mặt bảo mật. Sau khi build image, Trivy quét lỗ hổng. Nếu phát hiện lỗ hổng **CRITICAL**, pipeline dừng ngay lập tức và image không được publish. Lỗ hổng **HIGH** cũng chặn pipeline, trừ khi biến **RAFTDB_ACCEPT_HIGH_CVES** được đặt bằng SHA của commit hiện tại — yêu cầu chủ sở hữu repository xác nhận rõ ràng.

Sau khi quét, job ghi lại file **raftdb-image-evidence.json** chứa commit SHA, Docker image ID, và kết quả scan. File evidence này đi theo image qua tất cả các stage tiếp theo.

---

### 4. Build Stage — Docker Image và Chain-of-Custody

Khi tất cả test pass, build stage tiến hành xây dựng Docker image và đẩy lên container registry.

#### Go Server Image (Đường Đi Tiêu Chuẩn)

Go server image tuân theo quy trình build-and-push đơn giản:

1. Build: **docker build -t awsplace-ecs -f go-ecs/Dockerfile go-ecs** — multi-stage build trên Alpine, tạo ra binary tối thiểu
2. Tag: Image được gắn tag bằng commit SHA và **latest**
3. Push lên ECR: Script **scripts/push-ecs-image.sh** xử lý ECR login, gắn tag, push, và xác minh digest — đảm bảo digest của image đã push khớp với bản đã build cục bộ

ECR repository (**awsplace-ecs**) được tạo tự động bởi **scripts/ensure-ecr-repository.sh** nếu chưa tồn tại. Script này cũng cấu hình:
- Scan on push — mọi image push lên ECR đều tự động được quét lỗ hổng
- Lifecycle policy — chỉ giữ lại 10 image gần nhất; image cũ hơn tự động bị xóa
- Immutable tag exclusion — các tag khớp pattern **raftdb-*** là immutable (không thể ghi đè), đảm bảo tính tái tạo

#### RaftDB Image (Đường Đi Chain-of-Custody)

RaftDB image tuân theo quy trình chain-of-custody chặt chẽ hơn. Mục tiêu là đảm bảo image được publish lên ECR hoàn toàn giống từng byte với image đã qua tất cả test và quét bảo mật:

1. **Build + Test + Scan** (không cần AWS credential): Job **raftdb-image** build image, chạy contract test, qualification test, migration test, và Trivy scan — tất cả đều không cần cloud credential nào. Image đã test được export thành Docker tarball qua **docker save** và truyền qua CI artifact cùng file evidence JSON. Các artifact này hết hạn sau 1 ngày — chúng chỉ cần tồn tại đủ lâu để publish job sử dụng trong cùng pipeline run.

2. **Xác minh danh tính**: Job **publish-raftdb-image** tải tarball về, load image bằng **docker load**, và xác minh Docker image ID khớp với giá trị ghi trong file evidence. Nếu ID không khớp, pipeline dừng ngay — có ai đó đã can thiệp vào artifact.

3. **OIDC Authentication**: Chỉ sau khi xác minh danh tính thành công, job mới assume AWS role. Điều này đảm bảo không có AWS credential nào khả dụng trong giai đoạn build hoặc test.

Cấu trúc triển khai dependency này (**raftdb-image** → **publish-raftdb-image**) trên GitHub Actions:

```yaml
publish-raftdb-image:
  needs: raftdb-image
  if: github.ref == 'refs/heads/main'
  permissions:
    id-token: write       # OIDC token chỉ được tạo ở job này
    contents: read
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: raftdb-image-${{ github.sha }}
    # Xác minh danh tính image TRƯỚC KHI trao đổi OIDC token
    - name: Load and verify tested image identity
      run: |
        EXPECTED_IMAGE_ID=$(jq -r '.imageId' raftdb-image-evidence.json)
        docker load --input raftdb-image.tar
        ACTUAL_IMAGE_ID=$(docker image inspect "raftdb:${GITHUB_SHA}" --format '{{.Id}}')
        if [ "$ACTUAL_IMAGE_ID" != "$EXPECTED_IMAGE_ID" ]; then
          echo "Loaded image ID does not match tested image evidence" >&2
          exit 1
        fi
    # Chỉ bây giờ: trao đổi OIDC token lấy AWS credential
    - uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: ap-southeast-1
```

4. **Immutable Tagging**: Image được tag **raftdb-<commit-sha>** và push lên ECR. Nếu tag đã tồn tại, job pull image hiện có và so sánh image ID — nó từ chối ghi đè tag đang trỏ đến image khác.

5. **Post-push Contract Test**: Sau khi push, job xóa sạch Docker cache cục bộ, pull image lại bằng digest (không phải bằng tag), và chạy lại container contract test. Bước này xác nhận image không bị hỏng sau khi đi qua ECR.

6. **Ghi nhận Evidence**: File **raftdb-publish-evidence.json** được lưu lại chứa ECR repository URI và digest. Deploy stage sẽ dùng file evidence này để xác minh image đang deploy.

Cần lưu ý rằng nếu Trivy phát hiện bất kỳ lỗ hổng CRITICAL nào, image sẽ không được publish và pipeline dừng lại. Với lỗ hổng HIGH, chủ sở hữu repository phải chấp nhận rõ ràng bằng cách đặt **RAFTDB_ACCEPT_HIGH_CVES** bằng SHA của commit hiện tại.

#### Lambda Image

Lambda handler xác thực cũng được đóng gói thành container:

```bash
docker build -t awsplace-lambda -f Dockerfile .
```

Image này bundle **index.js** và thư mục **lambda/** trên base image **node:24-alpine**. Nó được push lên cả GHCR (truy cập công khai) và GitLab Container Registry (để đồng bộ).

#### Tạo Release

Khi một tag được push:

- Trên GitHub, job **build-push** build cả hai image, push lên GHCR với semantic tag (**sha-**, tên branch, **latest**), và tạo GitHub Release với release note tự sinh.
- Trên GitLab, job **create-release** tạo GitLab Release thông qua **release-cli**.

---

### 5. Deploy Stage — CDK, Amplify, và ECS

Deploy stage chỉ chạy trên branch **main** và chỉ sau khi tất cả job test và build đều thành công. Stage này gồm nhiều bước thực hiện tuần tự.

#### Bước 1: Kiểm Tra Biến Môi Trường

Trước khi thao tác bất kỳ tài nguyên AWS nào, pipeline chạy **scripts/validate-deploy-env.sh**. Script này kiểm tra tất cả biến deployment bắt buộc đã được đặt đúng:

| Biến | Kiểm tra |
|------|----------|
| **SESSION_SECRET** | Phải có giá trị, không phải reference **${}** chưa được resolve |
| **DISCORD_CLIENT_ID** | Phải có giá trị |
| **DISCORD_CLIENT_SECRET** | Phải có giá trị |
| **DISCORD_REDIRECT_URI** | Phải có giá trị |
| **ADMIN_DISCORD_IDS** | Phải có giá trị |
| **FRONTEND_URL** | Phải có giá trị |
| **HOSTED_ZONE_ID** | Phải khớp pattern **Z[A-Z0-9]+** (Route 53 zone ID hợp lệ) |
| **RAFTDB_IMAGE_DIGEST** | Phải khớp **sha256:[64 ký tự hex]** — đảm bảo digest đến từ image đã được test |

Nếu bất kỳ biến nào thiếu, chứa reference chưa resolve, hoặc không đúng format, pipeline dừng lại trước khi assume AWS role.

#### Bước 2: Chuẩn Bị CloudFormation Stack

**scripts/prepare-cloudformation-deploy.sh** kiểm tra trạng thái hiện tại của CloudFormation stack **AwsplaceStack** và xử lý các trường hợp đặc biệt:

| Trạng thái Stack | Hành động |
|-------------------|----------|
| **CREATE_FAILED**, **ROLLBACK_COMPLETE**, **ROLLBACK_FAILED**, **DELETE_FAILED** | Tự động xóa stack (tối đa 2 lần thử) để CDK có thể tạo lại |
| **DELETE_IN_PROGRESS** | Chờ cho đến khi xóa xong |
| **UPDATE_ROLLBACK_FAILED** | Từ chối tiếp tục — cần can thiệp thủ công |
| **\*_IN_PROGRESS** | Từ chối tiếp tục — đang có operation khác chạy |
| Trạng thái ổn định bất kỳ | Tiến hành deployment |

Điều này ngăn CDK gặp trạng thái stack không thể deploy và sinh ra lỗi khó hiểu.

#### Bước 3: CDK Deploy

Lệnh deployment chính:

```bash
npx cdk deploy --require-approval never --no-strict --all --import-existing-resources
```

Các flag quan trọng:
- **--require-approval never** — deploy tự động, không hiện prompt xác nhận
- **--no-strict** — chấp nhận các warning không nghiêm trọng trong CDK synthesis
- **--import-existing-resources** — tái adopt các resource có physical name rõ ràng nếu stack được tạo lại sau failure

Lệnh này deploy tất cả tài nguyên AWS theo thứ tự dependency: VPC, DynamoDB table, S3 bucket, ECR, Secrets Manager, API Gateway, Lambda, ALB, ECS Fargate, CloudFront, Route 53, và Amplify.

#### Bước 4: Deploy Frontend Qua Amplify

Sau khi CDK hoàn thành, pipeline deploy frontend lên AWS Amplify Hosting bằng cách upload trực tiếp asset (không qua Git-based build):

1. Đọc **AmplifyAppId** và **AmplifyBranchName** từ CloudFormation stack output
2. Build frontend bằng **bash scripts/build-frontend.sh** — inject các brand token vào HTML template và copy static asset vào **dist/**
3. Nén thư mục **dist/** thành file zip
4. Gọi **aws amplify create-deployment** để lấy pre-signed S3 upload URL
5. Upload file zip qua **curl**
6. Gọi **aws amplify start-deployment** để kích hoạt deployment
7. Poll **aws amplify get-job** mỗi 10 giây cho đến khi deployment thành công (timeout 10 phút)

#### Bước 5: ECS Force Deployment

Sau khi frontend đã live, pipeline khởi động lại ECS Fargate service để cập nhật Go server image mới và các secret đã thay đổi:

```bash
aws ecs update-service --force-new-deployment \
  --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME"
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
```

Lệnh **wait services-stable** chặn cho đến khi task definition mới chạy ổn định, healthy, và các task cũ đã drain xong. Nếu ECS không thể ổn định service (ví dụ container mới liên tục crash), deployment circuit breaker sẽ tự động rollback về phiên bản trước.

Sau khi ổn định, pipeline in ra bảng tóm tắt hiển thị desired count, running count, và rollout state của PRIMARY deployment.

#### Bước 6: Kiểm Tra Sau Deploy

Bước cuối cùng là smoke test xác minh WebSocket endpoint hoạt động đúng:

```bash
node scripts/check-websocket-origin.mjs \
  "wss://ws.${DOMAIN_NAME}/ws" \
  "https://${DOMAIN_NAME}"
```

Script này thực hiện một WebSocket upgrade handshake đầy đủ (TLS, HTTP 101, xác minh Sec-WebSocket-Accept) với header Origin chính xác. Nếu handshake thất bại — do cấu hình DNS sai, thiếu ALB target, hoặc origin policy không đúng — pipeline báo lỗi ngay lập tức thay vì để deployment lỗi chạy trên production.

---

### 6. CI Utilities Docker Image

GitLab CI cần một custom runner image (**ci-utils**) cho deploy stage, vì các image Node.js hay Go tiêu chuẩn không có đủ công cụ cần thiết. Image này được định nghĩa trong **Dockerfile.ci-utils** và bao gồm:

| Công cụ | Mục đích |
|---------|----------|
| Node.js 24 | CDK synthesis và build frontend |
| Go 1.25 | Build Go ECS server |
| AWS CLI v2 | Tất cả API call đến AWS (STS, ECR, ECS, CloudFormation, Amplify) |
| Docker CLI | Build và push container image |
| jq | Xử lý JSON cho evidence file và stack output |
| zip/unzip | Đóng gói frontend asset cho Amplify |

Image này được build lại tự động khi **Dockerfile.ci-utils** hoặc **.gitlab-ci.yml** thay đổi, gắn tag bằng commit SHA và **main**, rồi push lên GitLab Container Registry.

GitHub Actions không cần image này vì runner **ubuntu-latest** đã có sẵn hầu hết công cụ, và pipeline sử dụng các setup action (**actions/setup-node**, **actions/setup-go**, **actions/setup-python**) cho phần còn lại.

---

### 7. Chiến Lược Caching

Cả hai pipeline đều sử dụng dependency caching để giảm thời gian build.

GitLab CI dùng shared cache theo branch:

```yaml
cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - lambda/node_modules/
    - cdk/node_modules/
    - /go/pkg/mod/
  policy: pull-push
```

GitHub Actions dựa vào caching tích hợp trong **actions/setup-node** và **actions/setup-go**, tự động cache **node_modules** và **$GOPATH/pkg/mod** dựa trên hash của lockfile.

Các job liên quan đến Docker (build image, scan) tắt caching hoàn toàn (**cache: []** trên GitLab) để tránh cache pollution — Docker layer là ephemeral và không nên persist giữa các lần chạy.

---

### 8. Hướng Dẫn Thiết Lập & Cấu Hình

Trước khi pipeline CI/CD có thể deploy lên AWS, cần cấu hình thủ công bốn bước tiên quyết:

#### Bước 1: Tạo IAM OIDC Identity Provider

Cả hai nền tảng CI (GitHub Actions và GitLab CI) đều xác thực với AWS qua OIDC. Cần tạo IAM Identity Provider cho mỗi nền tảng:

- **GitHub Actions**: Tạo OpenID Connect provider với URL **https://token.actions.githubusercontent.com** và audience là **sts.amazonaws.com**.
- **GitLab CI**: Tạo OpenID Connect provider với URL GitLab instance (ví dụ **https://git.namanhishere.com**) và audience trùng với URL đó.

Sau đó tạo IAM Role với trust policy giới hạn quyền truy cập theo repository và branch cụ thể. Cả hai nền tảng đều assume cùng một role (**AWS_ROLE_ARN**), và role này phải có quyền cho ECS, ECR, S3, DynamoDB, CloudFormation, Amplify, Secrets Manager, và các service khác trong stack.

#### Bước 2: Ủy Quyền Tên Miền Cho Route 53

Dự án sử dụng subdomain (ví dụ **place.namanhishere.com**) được quản lý bởi AWS Route 53 để phân giải DNS. Nếu tên miền gốc của bạn được quản lý bởi nhà cung cấp DNS bên ngoài (như Cloudflare), bạn cần ủy quyền subdomain cho Route 53 bằng cách thêm các bản ghi **NS** trỏ về name server của AWS.

Dưới đây là ví dụ cấu hình bản ghi NS trên Cloudflare, ủy quyền **place.namanhishere.com** cho Route 53:

![Ủy quyền tên miền — Bản ghi NS trên Cloudflare](/images/5-Workshop/5.4-CICD-Pipeline/753747574_1015957567992787_6550916551567091605_n.jpg)

Sau khi cấu hình, bạn có thể kiểm tra kết quả phân giải bản ghi NS từ terminal bằng lệnh `dig place.namanhishere.com NS`:

![Kiểm tra phân giải bản ghi NS tên miền bằng dig](/images/5-Workshop/5.4-CICD-Pipeline/756430488_3121594578036333_8322272973070305772_n.png)

Bốn bản ghi NS trỏ đến các name server của AWS Route 53 được gán cho hosted zone. Sau khi propagation hoàn tất, Route 53 có toàn quyền quản lý mọi bản ghi DNS dưới subdomain (bản ghi A cho ALB, API Gateway, Amplify, xác thực chứng chỉ ACM, v.v.).

**HOSTED_ZONE_ID** từ Route 53 là biến CI/CD bắt buộc — script deploy sẽ kiểm tra định dạng (phải bắt đầu bằng **Z** theo sau bởi ký tự chữ-số) trước khi chạy CDK deploy.

#### Bước 3: Cấu Hình Biến CI/CD

Stage deploy yêu cầu các biến sau phải được thiết lập dưới dạng secret có thuộc tính **protected** và **masked** trên nền tảng CI:

| Biến | Mô tả |
|------|-------|
| **AWS_ROLE_ARN** | ARN của IAM role để assume qua OIDC |
| **DOMAIN_NAME** | Subdomain được quản lý bởi Route 53 (ví dụ **place.namanhishere.com**) |
| **HOSTED_ZONE_ID** | ID hosted zone của Route 53 cho subdomain |
| **SESSION_SECRET** | Chuỗi hex 96 ký tự ngẫu nhiên để mã hóa session |
| **DISCORD_CLIENT_ID** | Client ID của ứng dụng Discord OAuth2 |
| **DISCORD_CLIENT_SECRET** | Client secret của ứng dụng Discord OAuth2 |
| **DISCORD_REDIRECT_URI** | URL callback OAuth2 (ví dụ **https://api.place.namanhishere.com/auth/callback**) |
| **ADMIN_DISCORD_IDS** | Danh sách Discord user ID của admin, phân cách bằng dấu phẩy |
| **FRONTEND_URL** | URL công khai của frontend (ví dụ **https://place.namanhishere.com**) |

Script deploy (**scripts/validate-deploy-env.sh**) kiểm tra tất cả biến bắt buộc đã được thiết lập và không rỗng trước khi thao tác bất kỳ tài nguyên AWS nào. Script cũng kiểm tra **HOSTED_ZONE_ID** đúng định dạng Route 53 và **RAFTDB_IMAGE_DIGEST** là digest SHA-256 hợp lệ.

#### Bước 4: Deploy Lần Đầu

Sau khi hoàn tất các bước trên, push một commit lên nhánh **main**. Pipeline sẽ:

1. Chạy tất cả test song song (Lambda, Go unit/Postgres/MiniStack, CDK, RaftDB)
2. Build và push Docker image (Go server lên ECR, RaftDB với chain-of-custody verification)
3. Chạy **cdk deploy** để provision toàn bộ stack AWS (VPC, DynamoDB, S3, ECS, ALB, API Gateway, Lambda, Amplify, Route 53, Secrets Manager)
4. Deploy frontend lên Amplify qua direct asset upload
5. Buộc ECS deployment mới để cập nhật image và secret mới nhất
6. Chạy smoke test sau deploy để xác minh WebSocket endpoint

Lần deploy đầu tiên thường mất 15–20 phút do CloudFormation phải tạo mới toàn bộ tài nguyên. Các lần deploy sau nhanh hơn vì chỉ cập nhật tài nguyên thay đổi.

---

### 9. Tổng Kết

Pipeline CI/CD của awsplace đảm bảo mỗi commit vào **main** đều trải qua quy trình nghiêm ngặt trước khi đến production:

1. Test song song phủ mọi component — Lambda (Node.js), Go server (unit + Postgres + MiniStack integration), CDK infrastructure, RaftDB (contract + security scan + fuzzing)
2. Xác thực hoàn toàn qua OIDC, không có static AWS credential ở bất kỳ đâu
3. Chain-of-custody cho RaftDB image — build, test, scan, và publish được tách thành các job riêng biệt với xác minh mật mã tại mỗi điểm chuyển giao
4. Kiểm tra biến môi trường trước khi thao tác bất kỳ tài nguyên AWS nào
5. Infrastructure-as-Code deployment qua CDK với khả năng tự động phục hồi stack ở trạng thái lỗi
6. Deploy frontend qua Amplify direct asset upload với polling và timeout
7. ECS rolling deployment với circuit breaker tự động rollback
8. Smoke test sau deploy xác minh WebSocket endpoint hoạt động đúng từ góc nhìn của trình duyệt

Thiết kế này đảm bảo một commit lỗi không thể âm thầm lên production — mọi cổng kiểm tra phải pass, mọi image phải được xác minh, và service đã deploy phải chứng minh hoạt động bình thường trước khi pipeline báo cáo thành công.