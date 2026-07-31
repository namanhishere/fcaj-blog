---
title: "Tài khoản AWS"
date: 2026-07-27
weight: 2
chapter: false
pre: " <b> 5.2.2 </b> "
---

## Chọn tài khoản

Sử dụng tài khoản AWS mà nhóm sẵn sàng thanh toán. Pipeline tạo các tài nguyên có phí: VPC, Application Load Balancer, tác vụ Fargate, bảng DynamoDB theo billing on-demand, lưu trữ S3, lưu trữ ECR, API Gateway, Amplify Hosting, CloudWatch Logs và truy vấn Route 53. Hãy thiết lập cảnh báo billing nếu dùng tài khoản cá nhân.

## Khóa vùng

Mọi lệnh trong pipeline đều chỉ định rõ `ap-southeast-1`. Điểm vào CDK `awsplace/cdk/bin/app.ts` mặc định dùng `ap-southeast-1` khi `CDK_DEFAULT_REGION` chưa đặt, nhưng pipeline đặt `AWS_REGION: ap-southeast-1` trong mỗi job. Điều này ngăn `AWS_DEFAULT_REGION` cũ lặng chuyển tài nguyên sang vùng khác.

## Ghi lại Account ID

Nhiều tên tài nguyên và ARN trong workshop này chứa số tài khoản AWS 12 chữ số. Trong các trang này, nó được viết là `ACCOUNT_ID`; nhóm hãy thay bằng số của mình.

```bash
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "$ACCOUNT_ID"
```

## Đăng nhập AWS CLI v2

Pipeline sử dụng OIDC, nhưng nhóm vẫn cần credentials AWS cục bộ cho các bước thiết lập trong phần này. Cài đặt AWS CLI v2 và chạy `aws login` để xác thực qua IAM Identity Center hoặc AWS CLI SSO.

```bash
aws login
```

Lệnh in ra một URL và mở phiên trình duyệt.

![AWS CLI login prompt](/images/5-Workshop/5.2-Prerequisite/awslogincli.png)

Trang trình duyệt yêu cầu nhóm xác nhận phiên.

![AWS sign-in confirmation](/images/5-Workshop/5.2-Prerequisite/awsloginui.png)

Sau khi đăng nhập, xác nhận vùng và danh tính:

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


Nếu lệnh in ra `Unable to locate credentials`, hãy khắc phục trước khi làm gì khác. Phần còn lại của workshop giả định lệnh này thành công.