---
title: "Quyền IAM"
date: 2026-07-27
weight: 3
chapter: false
pre: " <b> 5.2.3 </b> "
---

Repository hỗ trợ hai đường dẫn triển khai: lệnh CDK cục bộ từ shell, và GitLab CI qua OIDC. Đường dẫn GitLab CI là đường dẫn production. Đường dẫn cục bộ hữu ích cho phát triển, gỡ lỗi và bước `cdk bootstrap` ban đầu.

## Principal deploy cục bộ

Nếu nhóm chạy `npx cdk deploy` cục bộ, principal cần quyền tạo, cập nhật và xóa trên các dịch vụ liệt kê dưới đây. CDK tạo tài nguyên trên mười bảy dịch vụ. Hãy cấp theo tiền tố dịch vụ thay vì dùng `"Action": "*"` trên toàn bộ AWS.

| Tiền tố dịch vụ | Cần cho |
|---|---|
| `cloudformation` | Tạo và cập nhật `AwsplaceStack` |
| `sts` | Assume role deploy CDK bootstrap |
| `ssm` | Đọc tham số phiên bản CDK bootstrap |
| `iam` | Tạo ba role trong `cdk/lib/iam.ts` và truyền cho ECS và Lambda |
| `ec2` | VPC, subnet, bảng định tuyến, security group, ENI tác vụ |
| `ecr` | Repository `awsplace-ecs`, lifecycle policy và đẩy image |
| `ecs` | Cluster, định nghĩa tác vụ, service |
| `elasticloadbalancing` | ALB, target group, cả hai listener |
| `elasticfilesystem` | File system, mount target, access point |
| `s3` | Bucket snapshot cộng hai bucket import từ phần 5.2.4 |
| `lambda` | Hàm auth và cấu hình của nó |
| `apigateway` | HTTP API và route `$default` |
| `amplify` | App, nhánh `production`, liên kết domain tùy chỉnh |
| `route53` | Đọc hosted zone và ghi bản ghi xác thực và alias |
| `acm` | Yêu cầu và xác thực chứng chỉ wildcard |
| `secretsmanager` | Tạo và đọc `awsplace/app-secrets` |
| `logs` | Nhóm log ECS và cả hai luồng container |

Chính sách deploy thực tế cho principal cục bộ được hiển thị dưới đây. Chính sách đủ rộng cho lần deploy đầu tiên và khi lặp lại trên stack. Nếu tổ chức yêu cầu quyền chặt hơn, hãy giới hạn tài nguyên S3, DynamoDB và IAM theo tên cụ thể mà stack sử dụng.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "sts:AssumeRole",
        "ssm:GetParameter",
        "iam:*",
        "ec2:*",
        "ecr:*",
        "ecs:*",
        "elasticloadbalancing:*",
        "elasticfilesystem:*",
        "s3:*",
        "lambda:*",
        "apigateway:*",
        "amplify:*",
        "route53:*",
        "acm:*",
        "secretsmanager:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

Chạy `npx cdk diff` trước lần deploy đầu tiên. Nếu nó báo loại tài nguyên ngoài danh sách này, hãy cấp thêm dịch vụ đó. Mở rộng thành `"Action": "*"` là cách sửa sai.

## Role deploy GitLab CI (OIDC)

Pipeline production xác thực qua IAM OIDC identity provider và assume role deploy chuyên dụng. Role có tên `GitLabCDKDeployRole` và được hiển thị trong screenshot ở phần 5.2.7.

Chính sách trust dưới đây giới hạn role cho nhánh `main` của dự án `namanhishere/awsplace` trên instance GitLab `git.namanhishere.com`. Thay `ACCOUNT_ID` bằng số tài khoản AWS của nhóm.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/git.namanhishere.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "git.namanhishere.com:aud": "https://git.namanhishere.com"
        },
        "StringLike": {
          "git.namanhishere.com:sub": "project_path:namanhishere/awsplace:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

Claim `sub` trong token OIDC GitLab trông như sau:

```
project_path:namanhishere/awsplace:ref_type:branch:ref:main
```

Nếu nhóm muốn deploy từ nhánh khác, hãy mở rộng pattern `StringLike`. Ví dụ, để cho phép bất kỳ nhánh nào:

```
project_path:namanhishere/awsplace:ref_type:branch:ref:*
```

Để production, giữ nguyên giới hạn cho `main`.

Gắn các quyền cấp dịch vụ từ bảng deploy cục bộ vào `GitLabCDKDeployRole`. Pipeline không cần access key dài hạn. Nó nhận credentials tạm thời qua `sts:AssumeRoleWithWebIdentity` với thời hạn một giờ.

## Chi tiết IAM cần biết trước khi gỡ lỗi

Hai chi tiết quyền đáng biết trước khi chúng gây bất ngờ sau này:

- Role thực thi ECS nhận `secretsmanager:GetSecretValue` giới hạn trên một ARN secret. App container đọc secret khi khởi động tác vụ.
- Lambda nhận cùng giá secret dưới dạng biến môi trường plain inject tại thời điểm tổng hợp. Đổi secret yêu cầu redeploy Lambda; ECS chỉ cần khởi động lại tác vụ.