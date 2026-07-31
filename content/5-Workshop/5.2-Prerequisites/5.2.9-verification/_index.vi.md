---
title: "Xác minh"
date: 2026-07-27
weight: 9
chapter: false
pre: " <b> 5.2.9 </b> "
---

Trước khi đẩy commit đầu tiên lên `main`, hãy chạy qua danh sách kiểm tra này.

## Kiểm tra công cụ

```bash
docker --version
docker compose version
go version
node --version
npm --version
python3 --version
npx cdk --version
aws --version
jq --version
zip --version
curl --version
git --version
```

## Kiểm tra credentials AWS

```bash
aws sts get-caller-identity --region ap-southeast-1
```

Kết quả mong đợi:

```json
{
    "UserId": "AIDAEXAMPLEUSERID",
    "Account": "ACCOUNT_ID",
    "Arn": "arn:aws:iam::ACCOUNT_ID:user/your-deploy-user"
}
```

## Kiểm tra S3 bucket

```bash
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws s3api head-bucket --bucket "awsplace-canvas-${ACCOUNT_ID}" --region ap-southeast-1
aws s3api head-bucket --bucket "awsplace-exports-${ACCOUNT_ID}" --region ap-southeast-1
```

Cả hai lệnh nên thoát im lặng với mã 0.

## Kiểm tra ủy quyền DNS

```bash
dig place.namanhishere.com NS +short
```

Kết quả mong đợi:

```
ns-204.awsdns-25.com.
ns-1073.awsdns-06.org.
ns-595.awsdns-10.net.
ns-1827.awsdns-36.co.uk.
```

## Kiểm tra đường dẫn dự án GitLab

Xác nhận dự án GitLab nằm tại `https://git.namanhishere.com/namanhishere/awsplace` và nhánh `main` được bảo vệ. Chính sách trust trong phần 5.2.7 chỉ cho phép nhánh `main` assume role deploy.

## Kiểm tra biến CI/CD GitLab

Trong dự án GitLab, vào **Settings** → **CI/CD** → **Variables** và xác nhận tất cả biến bắt buộc từ phần 5.2.8 đã có, không trống và được masked/protected đúng cách.

## Danh sách kiểm tra trước khi bay

| Kiểm tra | Lệnh hoặc vị trí | Kết quả mong đợi |
|---|---|---|
| Công cụ đã cài | Khối kiểm tra phần 5.2.1 | Tất cả lệnh trả về số phiên bản |
| Credentials AWS | `aws sts get-caller-identity --region ap-southeast-1` | Trả về account và user ARN |
| S3 bucket | `aws s3api head-bucket` | Thoát im lặng mã 0 |
| Ủy quyền DNS | `dig place.namanhishere.com NS +short` | Bốn nameserver Route 53 |
| App Discord | Discord Developer Portal | Hai redirect URI và scope `identify` |
| OIDC provider | IAM → Identity providers | `git.namanhishere.com` trong danh sách |
| Role deploy | IAM → Roles | `GitLabCDKDeployRole` tồn tại với trust policy đúng |
| Biến GitLab | Settings → CI/CD → Variables | Tất cả biến bắt buộc đã đặt và protected |
| Nhánh được bảo vệ | GitLab → Repository → Branches | `main` được bảo vệ |

Nếu mọi kiểm tra đều qua, repository đã sẵn sàng cho lần deploy production đầu tiên. Đẩy commit lên `main` và theo dõi pipeline GitLab chạy.