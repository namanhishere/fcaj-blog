---
title: "Thiết lập OIDC với GitLab Runner tự host"
date: 2026-07-27
weight: 7
chapter: false
pre: " <b> 5.2.7 </b> "
---

Pipeline production sử dụng OpenID Connect để xác thực với AWS mà không lưu credentials dài hạn trong GitLab. Đây là mô hình bảo mật tương tự mô tả trong phần [CI/CD Pipeline](../5.4-CICD-Pipeline/).

## Tại sao dùng OIDC?

Nếu không có OIDC, nhóm cần lưu access key và secret key AWS trong biến CI/CD GitLab. Nếu những biến đó bị rò rỉ, kẻ tấn công có quyền truy cập liên tục vào tài khoản. Với OIDC, GitLab cung cấp JWT token có chữ ký ngắn hạn cho mỗi lần chạy pipeline. AWS STS đổi token đó lấy credentials tạm thời hết hạn sau một giờ. Không có credentials AWS dài hạn nào trong GitLab.

## Bước 1: Tạo IAM OIDC identity provider

1. Mở IAM console.
2. Vào **Identity providers** → **Add provider**.
3. Chọn **OpenID Connect**.
4. Ở **Provider URL**, nhập `https://git.namanhishere.com`.
5. Ở **Audience**, nhập `https://git.namanhishere.com`.
6. Nhấn **Get thumbprint** để lấy dấu vân tay chứng chỉ TLS tự động.
7. Nhấn **Add provider**.

Screenshot dưới đây hiển thị IAM OIDC provider cho `git.namanhishere.com` với audience `https://git.namanhishere.com`.

![IAM OIDC provider for GitLab](/images/5-Workshop/5.2-Prerequisite/IAM_OIDC.png)

## Bước 2: Tạo IAM role

1. Trong IAM console, vào **Roles** → **Create role**.
2. Chọn **Web identity**.
3. Ở **Identity provider**, chọn `git.namanhishere.com`.
4. Ở **Audience**, chọn `https://git.namanhishere.com`.
5. Ở **GitLab branch**, nhóm có thể cần nhập `main` hoặc để trống và sửa trust policy thủ công sau khi tạo.
6. Đặt tên role `GitLabCDKDeployRole`.

Sau khi tạo, thay trust policy tự tạo bằng JSON này. Thay `ACCOUNT_ID` bằng số tài khoản AWS.

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

Screenshot dưới đây hiển thị `GitLabCDKDeployRole` với thời lượng phiên tối đa 1 giờ.

![GitLab CDK deploy role](/images/5-Workshop/5.2-Prerequisite/IAMDeployRole.png)

## Bước 3: Gắn chính sách triển khai

Gắn quyền cấp dịch vụ từ phần 5.2.3 vào role. Nhóm có thể dùng cùng JSON chính sách ở đó.

## Bước 4: Kiểm tra luồng OIDC

Cách dễ nhất để kiểm tra là kích hoạt pipeline trong GitLab và theo dõi job `deploy-to-aws`. Nếu assume role thất bại, nhật ký job sẽ hiển thị lỗi từ `aws sts assume-role-with-web-identity`.

Nếu muốn kiểm tra thủ công, nhóm cần JWT token GitLab OIDC hợp lệ. Job GitLab CI tự động làm việc này:

```bash
ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity \
  --role-arn "arn:aws:iam::ACCOUNT_ID:role/GitLabCDKDeployRole" \
  --role-session-name "GitLabCI-test" \
  --web-identity-token "$GITLAB_JWT_TOKEN" \
  --duration-seconds 3600 \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text)
```

Kiểm tra thành công trả về credentials tạm thời. Thất bại thường do một trong các giá trị sau sai:

- Provider URL hoặc audience không khớp GitLab.
- Điều kiện `sub` trong trust policy không khớp đường dẫn dự án hoặc nhánh.
- Role ARN không đúng.
- JWT token GitLab đã hết hạn.

## Bước 5: Lưu role ARN

Copy role ARN:

```
arn:aws:iam::ACCOUNT_ID:role/GitLabCDKDeployRole
```

Lưu giá trị này vào biến GitLab CI/CD `AWS_ROLE_ARN` như mô tả trong phần 5.2.8.