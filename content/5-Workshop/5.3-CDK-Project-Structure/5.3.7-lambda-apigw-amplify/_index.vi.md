---
title : "Lambda, API Gateway & Amplify"
date : 2024-01-01
weight : 7
chapter : false
pre : " <b> 5.3.7 </b> "
---

Phần này bao gồm ba module cùng nhau tạo thành lớp phục vụ frontend và xác thực: **Lambda** cho OAuth + admin proxy, **API Gateway** cho định tuyến HTTP, và **Amplify** cho lưu trữ frontend.

![Sơ đồ Lớp Serverless](/images/5-Workshop/5.3-CDK-Project-Structure/serverless-layer.png)

---

#### Lambda

Module Lambda (**createLambda**) tạo một **hàm Lambda Node.js 24** và một **Secrets Manager secret**.

```typescript
export function createLambda(scope: Construct, input: LambdaInput): LambdaOutput {
  const appSecret = new secretsmanager.Secret(scope, 'AppSecret', {
    secretName: 'awsplace/app-secrets',
    secretStringValue: SecretValue.unsafePlainText(JSON.stringify({
      SESSION_SECRET: sessionSecretValue,
      DISCORD_CLIENT_ID: discordClientId,
      DISCORD_CLIENT_SECRET: discordClientSecret,
      DISCORD_REDIRECT_URI: discordRedirectUri,
      ADMIN_DISCORD_IDS: adminDiscordIds,
    })),
  });
  appSecret.applyRemovalPolicy(RemovalPolicy.RETAIN);

  const apiFunction = new lambda.Function(scope, 'ApiFunction', {
    runtime: lambda.Runtime.NODEJS_24_X,
    handler: 'index.handler',
    code: lambda.Code.fromAsset('../lambda'),
    role: iam.lambdaExecutionRole,
    timeout: Duration.seconds(30),
    memorySize: 512,
    environment: { NODE_ENV: 'production', ... },
  });

  return { apiFunction, appSecret };
}
```

**Thông số Lambda:**

| Cài đặt | Giá trị | Lý do |
|---------|--------|-------|
| Runtime | Node.js 24 (NODEJS_24_X) | Runtime Node.js mới nhất hiện có |
| Bộ nhớ | 512 MB | Đủ cho Express + JWT + proxy |
| Thời gian chờ | 30 giây | Bao gồm trao đổi OAuth Discord (lên đến ~10s) + chuyển tiếp proxy |
| Handler | index.handler | Điểm vào bọc Express qua @vendia/serverless-express |
| Mã nguồn | Thư mục ../lambda | Được triển khai dưới dạng asset từ hệ thống file cục bộ |

**Trách nhiệm của Lambda:**

1. **Auth routes** (/auth/login, /auth/callback, /auth/logout, /api/me) — Luồng Discord OAuth2 với token phiên JWT HS256 (hết hạn 7 ngày, cookie rplace_session).
2. **Admin proxy** (/api/admin/*) — Chuyển tiếp yêu cầu admin đến ECS ALB sau khi thực thi requireSameOrigin trên mutation và requireAdmin trên tất cả các route.

**Secrets Manager secret:**

Secret awsplace/app-secrets lưu trữ một đối tượng JSON với 5 trường. Secret này có RemovalPolicy.RETAIN để stack bị hủy có thể nhập lại ngay lập tức (cửa sổ khôi phục Secrets Manager nếu không sẽ giữ tên).

**Quan trọng: đồng bộ secret.** Lambda nhận giá trị secret tại **thời điểm tổng hợp CDK** qua biến môi trường. ECS nhận chúng tại **thời điểm khởi động container** qua trường secrets. Khi xoay secret, Lambda phải được triển khai lại; ECS nhận giá trị mới khi task khởi động lại.

---

#### API Gateway

Module API Gateway (**createApiGateway**) tạo một **HTTP API v2** (không phải REST API v1) với một route $default duy nhất chuyển tiếp tất cả yêu cầu đến hàm Lambda.

```typescript
export function createApiGateway(scope, lambda, input): ApiGatewayOutput {
  const api = new apigatewayv2.HttpApi(scope, 'ApiGateway', {
    corsPreflight: {
      allowOrigins: ['https://place.namanhishere.com'],
      allowMethods: [GET, POST, PUT, DELETE, OPTIONS],
      allowHeaders: ['content-type', 'authorization'],
      allowCredentials: true,
      maxAge: Duration.days(1),
    },
    defaultIntegration: new integrations.HttpLambdaIntegration(
      'LambdaIntegration', lambda.apiFunction
    ),
  });

  // Tên miền tùy chỉnh: api.<domainName>
  const apiDomainName = new apigatewayv2.DomainName(scope, 'CustomDomain', {
    domainName: `api.${domainName}`,
    certificate: wildcardCert,
  });

  new apigatewayv2.ApiMapping(scope, 'ApiMapping', {
    api, domainName: apiDomainName, stage: api.defaultStage!,
  });

  // Route 53: api.<domainName> → API Gateway
  new route53.ARecord(scope, 'ApiRecord', {
    zone: hostedZone, recordName: `api.${domainName}`,
    target: route53.RecordTarget.fromAlias(
      new targets.ApiGatewayv2DomainProperties(
        apiDomainName.regionalDomainName,
        apiDomainName.regionalHostedZoneId
      )
    ),
  });
}
```

**Tại sao HTTP API v2 (không phải REST API v1)?**

| Yếu tố | HTTP API v2 | REST API v1 |
|--------|-------------|-------------|
| Chi phí mỗi yêu cầu | ~$1.00/triệu | ~$3.50/triệu |
| Khởi động lạnh | Nhanh hơn | Chậm hơn |
| Tính năng | Đơn giản hơn (không API keys, usage plans, request validation) | Nhiều tính năng hơn |
| Định dạng payload | 2.0 | 1.0 hoặc 2.0 |

Đối với ứng dụng này, Lambda xử lý tất cả định tuyến nội bộ qua Express — API Gateway chỉ cần chuyển mọi thứ qua. HTTP API v2 là lựa chọn đơn giản hơn, rẻ hơn.

**Cấu hình CORS:** Cài đặt CORS preflight cho phép rõ ràng origin frontend với allowCredentials: true. Điều này cho phép frontend gửi cookie (rplace_session) trên các cuộc gọi API chéo subdomain.

**Kiến trúc tên miền phân tách:**

```
┌────────────────────────────────────────────────────────────┐
│  Route 53 Hosted Zone: place.namanhishere.com              │
│                                                            │
│  domain.com          → Amplify (TLS được quản lý)          │
│  ├── /               → Canvas SPA (index.html)             │
│  └── /admin.html     → Admin SPA (file .html thực)         │
│                                                            │
│  api.domain.com      → API Gateway (wildcard cert)         │
│  ├── /auth/*         → Lambda: Discord OAuth               │
│  ├── /api/me         → Lambda: Thông tin session           │
│  └── /api/admin/*    → Lambda: Proxy tới ECS               │
│                                                            │
│  ws.domain.com       → ALB (wildcard cert)                 │
│  └── wss://          → ECS: Kết nối WebSocket              │
└────────────────────────────────────────────────────────────┘
```

- **Cookie domain**: Tên miền cha (được chia sẻ, để cookie được đặt bởi api. có thể nhìn thấy bởi tên miền gốc)

---

#### Amplify Hosting

Module Amplify (**createAmplify**) tạo một ứng dụng Amplify Hosting cho frontend.

```typescript
export function createAmplify(scope: Construct, props: AmplifyProps): AmplifyOutput {
  const app = new amplify.App(scope, 'AmplifyApp', { appName });

  // Quy tắc viết lại SPA — giữ file .html cho admin dashboard
  app.addCustomRule(new amplify.CustomRule({
    source: '</^[^.]+$|\\.(?!(css|...|html)$)([^.]+$)/>',
    target: '/index.html',
    status: amplify.RedirectStatus.REWRITE,
  }));

  app.addCustomRule(new amplify.CustomRule({
    source: '/<*>', target: '/index.html',
    status: amplify.RedirectStatus.NOT_FOUND_REWRITE,
  }));

  const branch = app.addBranch('production', { branchName: 'production' });
  const domain = app.addDomain(domainName, { enableAutoSubdomain: false });
  domain.mapRoot(branch);

  return { app, branch, domain };
}
```

**Lựa chọn thiết kế chính:**

1. **Không có source-code provider**: Frontend được triển khai dưới dạng asset .zip từ CI, không được kéo từ CodeCommit/GitHub. Điều này cho phép kiểm soát hoàn toàn quá trình build.

2. **SPA rewrite với ngoại lệ admin**: Quy tắc tùy chỉnh đầu tiên viết lại các đường dẫn không có phần mở rộng thành /index.html (hành vi SPA tiêu chuẩn), nhưng quan trọng là bao gồm html trong danh sách cho phép phần mở rộng. Điều này có nghĩa là /admin.html được phục vụ như một file thực, không bị viết lại thành SPA shell canvas.

3. **TLS do Amplify quản lý**: Amplify cung cấp chứng chỉ ACM riêng cho tên miền gốc. Điều này tách biệt với wildcard ACM cert được sử dụng cho subdomain api. và ws.

4. **Không auto-subdomain**: enableAutoSubdomain: false ngăn Amplify tạo bản ghi subdomain có thể xung đột với bản ghi Route 53 đã được tạo bởi các module khác.

**Luồng triển khai frontend (CI):**
```
1. Build: bash scripts/build-frontend.sh → dist/ (chèn brand tokens + WS_URL)
2. Zip:   cd dist && zip -r ../frontend.zip .
3. Slot:  aws amplify create-deployment → jobId + URL tải lên có chữ ký sẵn
4. Upload: curl --upload-file frontend.zip $UPLOAD_URL
5. Start: aws amplify start-deployment --job-id $JOB_ID
6. Poll:  aws amplify get-job cho đến khi SUCCEED/FAILED
```
