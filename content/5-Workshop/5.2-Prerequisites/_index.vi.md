---
title: "Các bước chuẩn bị"
date: 2026-07-27
weight: 2
chapter: false
pre: " <b> 5.2. </b> "
---

Workshop này triển khai **awsplace** (bản clone r/place) lên AWS thông qua **GitLab CI** trên runner tự host tại `https://git.namanhishere.com/namanhishere/awsplace`. Mọi tài nguyên AWS được tạo trong vùng `ap-southeast-1`.

Các bước chuẩn bị được chia thành mười một phần con. Hãy thực hiện theo thứ tự trước khi push commit lên nhánh `main` của repository GitLab.

| Phần con | Mô tả |
|---|---|
| [5.2.1 Phần mềm](5.2.1-software/) | Các công cụ cần thiết, phiên bản và lệnh kiểm tra |
| [5.2.2 Tài khoản AWS](5.2.2-aws-account/) | Chọn tài khoản AWS, khóa vùng `ap-southeast-1` và đăng nhập AWS CLI |
| [5.2.3 Quyền IAM](5.2.3-iam-permissions/) | Quyền principal deploy cục bộ và chính sách trust role OIDC GitLab CI |
| [5.2.4 Tài nguyên AWS cần thiết](5.2.4-required-aws-resources/) | CDK bootstrap, tạo S3 bucket và các tài nguyên CDK tạo tự động |
| [5.2.5 Thiết lập ứng dụng Discord](5.2.5-setup-discord-application/) | Discord Developer Portal, redirect URI OAuth2, scope `identify` và quyền admin |
| [5.2.6 Cấu hình subdomain đến Route53 từ Cloudflare](5.2.6-config-subdomain-to-route53-from-cloudflare/) | Route 53 hosted zone, ủy quyền NS từ Cloudflare và xác minh DNS |
| [5.2.7 Thiết lập OIDC với GitLab Runner tự host](5.2.7-setup-oidc-with-selfhost-gitlab-runner/) | IAM OIDC provider, `GitLabCDKDeployRole`, trust policy và kiểm tra OIDC |
| [5.2.8 Biến môi trường — Thiết lập với GitLab](5.2.8-environment-variables-setup-with-gitlab/) | Biến CI/CD GitLab, thiết lập masked/protected và script kiểm tra |
| [5.2.9 Xác minh](5.2.9-verification/) | Kiểm tra pre-flight cho công cụ, credentials, S3 bucket, DNS và biến GitLab |
| [5.2.10 Thiết lập AWS cục bộ](5.2.10-local-aws-setup/) | Môi trường phát triển cục bộ MiniStack + Docker Compose (tùy chọn) |
| [5.2.11 An toàn Sandbox CLI](5.2.11-cli-sandbox-safety/) | Sandbox Docker tùy chọn để thao tác CDK/AWS CLI an toàn và cách ly |

Các phần **5.2.1** đến **5.2.9** là bắt buộc cho deployment GitLab production. Các phần **5.2.10** và **5.2.11** là tùy chọn nhưng được khuyến nghị cho phát triển cục bộ, gỡ lỗi và thao tác CLI an toàn.

Để biết thêm chi tiết về pipeline sau khi hoàn thành các bước chuẩn bị, xem phần [CI/CD Pipeline](../5.4-CICD-Pipeline/).
