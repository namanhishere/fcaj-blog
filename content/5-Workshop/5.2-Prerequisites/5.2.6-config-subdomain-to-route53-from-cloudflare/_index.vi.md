---
title: "Cấu hình subdomain đến Route53 từ Cloudflare"
date: 2026-07-27
weight: 6
chapter: false
pre: " <b> 5.2.6 </b> "
---

Domain workshop là `place.namanhishere.com`. DNS được ủy quyền từ Cloudflare sang AWS Route 53 public hosted zone. Điều này cho phép Route 53 quản lý bản ghi cho ALB, API Gateway và Amplify mà không cần chuyển toàn bộ domain gốc sang AWS.

## Bước 1: Tạo Route 53 hosted zone

1. Mở Route 53 console trong vùng `ap-southeast-1`.
2. Nhấn **Hosted zones** → **Create hosted zone**.
3. Nhập domain `place.namanhishere.com`.
4. Chọn **Public hosted zone**.
5. Nhấn **Create hosted zone**.

Route 53 gán bốn nameserver. Workshop này dùng:

- `ns-204.awsdns-25.com`
- `ns-1073.awsdns-06.org`
- `ns-595.awsdns-10.net`
- `ns-1827.awsdns-36.co.uk`

Hosted zone ID cho workshop này là `Z0456501936MVLQCQV3O6Y`. Nhóm sẽ lưu giá trị này vào biến GitLab CI/CD `HOSTED_ZONE_ID`.

## Bước 2: Copy nameserver

Sau khi tạo zone, trang chi tiết Route 53 hiển thị nameserver và hosted zone ID.

![Route 53 hosted zone for place.namanhishere.com](/images/5-Workshop/5.2-Prerequisite/route53.png)

## Bước 3: Thêm bản ghi NS trong Cloudflare

1. Mở Cloudflare dashboard cho domain gốc `namanhishere.com`.
2. Vào **DNS** → **Records**.
3. Thêm bốn bản ghi `NS` cho subdomain `place`.
4. Mỗi bản ghi `NS` trỏ đến một nameserver Route 53.
5. Giữ TTL ở **Auto**.

Screenshot dưới đây hiển thị bản ghi DNS Cloudflare cho ủy quyền.

![Cloudflare NS records pointing to Route 53](/images/5-Workshop/5.2-Prerequisite/cloudflare.png)

## Bước 4: Chờ propagation

Thay đổi bản ghi NS có thể mất từ vài phút đến vài giờ để propagate, tùy TTL của zone gốc. Bản ghi `NS` Cloudflare với TTL **Auto** thường propagate nhanh.

## Bước 5: Xác minh bằng `dig`

Chạy lệnh này từ máy cục bộ:

```bash
dig place.namanhishere.com NS
```

Kết quả nên liệt kê bốn nameserver Route 53.

![dig output for place.namanhishere.com NS records](/images/5-Workshop/5.2-Prerequisite/digcheck.png)

Cũng có thể dùng `+short` để xem gọn:

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

## Tại sao dùng NS record mà không phải CNAME?

`CNAME` ở đỉnh subdomain có thể xung đột với các loại bản ghi khác như `SOA` và `NS`. Ủy quyền toàn bộ subdomain `place.namanhishere.com` cho Route 53 bằng bản ghi `NS` cho phép AWS kiểm soát hoàn toàn mọi bản ghi dưới subdomain đó, bao gồm bản ghi `A` apex cho Amplify, alias `api` cho API Gateway và alias `ws` cho ALB.