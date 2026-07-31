---
title: "Tài nguyên AWS cần thiết"
date: 2026-07-27
weight: 4
chapter: false
pre: " <b> 5.2.4 </b> "
---

## CDK bootstrap

CDK CLI cần bootstrap stack trong `ap-southeast-1` để lưu asset và cấp quyền triển khai. Bootstrap vùng một lần trước khi deploy đầu tiên:

```bash
npx cdk bootstrap aws://ACCOUNT_ID/ap-southeast-1
```

Lệnh tạo CloudFormation stack tên `CDKToolkit` và S3 bucket để staging asset. Nếu nhóm đã bootstrap tài khoản và vùng này cho dự án khác, có thể bỏ qua bước này.

## Hai S3 bucket phải tạo

CDK stack tạo hầu hết tài nguyên tự động, nhưng hai S3 bucket phải tồn tại trước lần deploy đầu tiên. Stack import chúng theo tên trong `awsplace/cdk/lib/storage.ts`:

```typescript
const canvasBucket = s3.Bucket.fromBucketName(
  scope,
  'ImportedCanvasBucket',
  `awsplace-canvas-${account}`
);
```

Bucket import là tham chiếu, không phải tài nguyên. CloudFormation sẽ không tạo nó, và stack không xác nhận nó tồn tại, nên bucket thiếu sẽ xuất hiện dưới dạng lỗi truy cập runtime từ container đang chạy thay vì lỗi tổng hợp rõ ràng.

Tạo cả hai bucket trong `ap-southeast-1` trước lần `cdk deploy` đầu tiên:

| Bucket | Mục đích |
|---|---|
| `awsplace-canvas-ACCOUNT_ID` | Snapshot canvas nhị phân do Go server ghi |
| `awsplace-exports-ACCOUNT_ID` | PNG export và artifact timelapse |

```bash
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws s3api create-bucket \
  --bucket "awsplace-canvas-${ACCOUNT_ID}" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api create-bucket \
  --bucket "awsplace-exports-${ACCOUNT_ID}" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

Kiểm tra bucket tồn tại:

```bash
aws s3api head-bucket --bucket "awsplace-canvas-${ACCOUNT_ID}" --region ap-southeast-1
aws s3api head-bucket --bucket "awsplace-exports-${ACCOUNT_ID}" --region ap-southeast-1
```

Thoát im lặng với mã 0 nghĩa là bucket đã có. `404` nghĩa là vẫn cần tạo. `403` nghĩa là tên đã bị tài khoản khác chiếm, điều này không nên xảy ra vì tên chứa số tài khoản của nhóm.

## Tài nguyên CDK stack tạo

CDK stack `AwsplaceStack` tạo các tài nguyên sau theo thứ tự phụ thuộc:

| Tài nguyên | CDK module | Mục đích |
|---|---|---|
| VPC với hai subnet công khai | `cdk/lib/vpc.ts` | Mạng cho ECS và EFS; không có NAT gateway |
| Bảng DynamoDB `Config`, `Bans`, `Milestones`, `History` | `cdk/lib/database.ts` | Dữ liệu legacy/migration; billing on-demand |
| ECR repository `awsplace-ecs` | `cdk/lib/ecr.ts` | Lưu image Go server và RaftDB; giữ 10 image cuối |
| S3 bucket import `awsplace-canvas-*`, `awsplace-exports-*` | `cdk/lib/storage.ts` | Snapshot canvas và PNG export |
| IAM role cho ECS thực thi, ECS task và Lambda | `cdk/lib/iam.ts` | Role runtime quyền tối thiểu |
| EFS và S3 snapshot storage cho RaftDB | `cdk/lib/raftdb-application.ts` | Lưu trữ bền vững cho RaftDB sidecar |
| Chứng chỉ ACM wildcard cho `*.place.namanhishere.com` | `cdk/lib/route53.ts` | TLS cho ALB và API Gateway |
| Secrets Manager secret `awsplace/app-secrets` | `cdk/lib/lambda.ts` | Lưu secret Discord và session |
| Hàm Lambda cho Discord OAuth và admin proxy | `cdk/lib/lambda.ts` | Runtime Node.js 24 |
| API Gateway HTTP API v2 với domain tùy chỉnh `api.place.namanhishere.com` | `cdk/lib/apigw.ts` | Định tuyến `/auth/*` và `/api/*` đến Lambda |
| ECS Fargate service và ALB | `cdk/lib/ecs.ts` | Chạy Go server và RaftDB sidecar |
| Amplify Hosting app với nhánh `production` | `cdk/lib/amplify.ts` | Phục vụ frontend tĩnh |
| Bản ghi Route 53 và nhóm log CloudWatch | `cdk/lib/route53.ts`, stack output | DNS và observability |

Lần deploy đầu tiên thường mất 15–20 phút vì CloudFormation tạo tất cả tài nguyên này từ đầu.

## Ghi chú về ECR repository

ECR repository `awsplace-ecs` được CDK stack tạo với `RemovalPolicy.RETAIN`. Nghĩa là nó tồn tại sau `cdk destroy` và có thể import lại ở lần deploy tiếp theo. Repository sử dụng `TagMutability.MUTABLE_WITH_EXCLUSION` nhưng loại trừ tag khớp `raftdb-*` khỏi mutation, nên image RaftDB là bất biến sau khi đẩy.