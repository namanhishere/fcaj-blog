---
title: "Biến môi trường — Thiết lập với GitLab"
date: 2026-07-27
weight: 8
chapter: false
pre: " <b> 5.2.8 </b> "
---

Pipeline triển khai xác nhận biến bắt buộc bằng `awsplace/scripts/validate-deploy-env.sh`. Script từ chối khởi động nếu biến thiếu, trống hoặc chứa tham chiếu `${...}` chưa giải quyết.

## Nơi đặt biến

1. Mở dự án GitLab tại `https://git.namanhishere.com/namanhishere/awsplace`.
2. Vào **Settings** → **CI/CD** → **Variables**.
3. Nhấn **Add variable**.
4. Nhập key, value và type.
5. Đánh dấu giá trị nhạy cảm là **Masked** và **Protected**.

## Biến bắt buộc

| Biến | Giá trị | Masked | Protected | Mục đích |
|---|---|---|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/GitLabCDKDeployRole` | Có | Có | IAM role job deploy assume qua OIDC |
| `HOSTED_ZONE_ID` | `Z0456501936MVLQCQV3O6Y` | Không | Có | Route 53 hosted zone ID cho `place.namanhishere.com` |
| `DOMAIN_NAME` | `place.namanhishere.com` | Không | Có | Domain cơ sở dùng cho ALB, API Gateway và Amplify |
| `SESSION_SECRET` | Chuỗi hex ngẫu nhiên 96 ký tự | Có | Có | Key ký JWT session cookie |
| `DISCORD_CLIENT_ID` | `1510122461088448633` | Có | Có | Discord OAuth2 Client ID |
| `DISCORD_CLIENT_SECRET` | Từ trang OAuth2 Discord | Có | Có | Discord OAuth2 Client Secret |
| `DISCORD_REDIRECT_URI` | `https://api.place.namanhishere.com/auth/callback` | Không | Có | URL callback OAuth2; phải khớp cài đặt app Discord |
| `ADMIN_DISCORD_IDS` | Discord user ID phân cách bằng dấu phẩy | Có | Có | Người dùng được phép vào admin dashboard |
| `FRONTEND_URL` | `https://place.namanhishere.com` | Không | Có | URL công khai của frontend |
| `RAFTDB_IMAGE_DIGEST` | Do job `publish-raftdb-image` cung cấp | Không | Có | Digest bất biến của image RaftDB đã kiểm tra |

## Tạo session secret

Tạo chuỗi hex ngẫu nhiên 96 ký tự:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Copy kết quả vào biến `SESSION_SECRET`. Không lưu vào file.

## Digest image RaftDB

`RAFTDB_IMAGE_DIGEST` là giá trị duy nhất nhóm không thể chuẩn bị trước. Validator yêu cầu đúng định dạng `sha256:[0-9a-f]{64}` để RaftDB không bao giờ deploy bằng tag có thể thay đổi. Job `publish-raftdb-image` trong `.gitlab-ci.yml` tạo digest này và truyền cho job deploy dưới dạng artifact dotenv.

## Biến tùy chọn

| Biến | Giá trị | Mục đích |
|---|---|---|
| `RAFTDB_ACCEPT_HIGH_CVES` | Commit SHA hiện tại | Nếu quét Trivy phát hiện lỗ hổng HIGH trong image RaftDB, đặt biến này thành commit SHA cho phép pipeline tiếp tục sau khi chủ sở hữu xác nhận rõ ràng |

## Biến tích hợp không nên định nghĩa lại

GitLab tự động cung cấp những biến này. Không tự định nghĩa:

- `CI_REGISTRY_USER`
- `CI_REGISTRY_PASSWORD`
- `CI_REGISTRY`
- `CI_REGISTRY_IMAGE`
- `CI_COMMIT_SHA`
- `CI_COMMIT_REF_SLUG`
- `CI_PIPELINE_ID`
- `CI_PROJECT_DIR`

## Biến protected

Đánh dấu biến liên quan triển khai là **Protected**. Điều này đảm bảo chúng chỉ được inject vào pipeline chạy trên nhánh được bảo vệ (thường là `main`). Pipeline merge request sẽ không nhận những giá trị này, ngăn triển khai ngẫu nhiên từ nhánh feature.

## Xác nhận

Script `validate-deploy-env.sh` kiểm tra từng biến bắt buộc. Lỗi thường trông như thế này:

```
ERROR: required deployment variable HOSTED_ZONE_ID is not set
ERROR: required deployment variable RAFTDB_IMAGE_DIGEST contains an unresolved variable reference
```

Sửa biến và chạy lại pipeline.