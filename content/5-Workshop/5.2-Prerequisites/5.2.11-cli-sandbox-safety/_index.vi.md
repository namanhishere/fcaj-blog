---
title: "An toàn Sandbox CLI (tùy chọn)"
date: 2026-07-27
weight: 11
chapter: false
pre: " <b> 5.2.11 </b> "
---

CDK CLI và AWS CLI chạy với quyền mạnh mẽ. Một lỗi đánh máy trong lệnh `cdk deploy` hoặc `aws s3 rm` trên máy host có thể vô tình ảnh hưởng đến dự án hoặc profile AWS khác. Repository awsplace bao gồm Docker sandbox nhẹ trong `awsplace/cdk/Dockerfile` cách ly các công cụ này khỏi môi trường host.

Phần này là tùy chọn nhưng được khuyến nghị mạnh mẽ cho bất kỳ thao tác CLI thủ công nào trên stack.

## Tại sao dùng sandbox?

| Lợi ích | Giải thích |
|---|---|
| **Cách ly credentials** | Container không kế thừa thư mục `~/.aws` của host. Phiên AWS không rò rỉ giữa host và container. |
| **Ghim phiên bản** | Mọi người chạy cùng Node.js 24, AWS CLI v2 và CDK CLI, bất kể host cài gì. |
| **Khả năng tái tạo** | Lệnh chạy được trong sandbox sẽ chạy được với mọi thành viên nhóm. Không có vấn đề "chạy được trên máy tôi". |
| **Thử nghiệm an toàn** | Nhóm có thể chạy `cdk diff`, `cdk deploy` hoặc `cdk destroy` mà không lo nhầm profile AWS trên host. |

## Dockerfile

`awsplace/cdk/Dockerfile` là image tối giản dựa trên `node:24-bookworm`:

```dockerfile
FROM node:24-bookworm

# AWS CLI v2
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    less \
    groff \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# AWS CDK
RUN npm install -g aws-cdk

WORKDIR /workspace

CMD ["/bin/bash"]

# Build using docker build -t aws-bootstrap -f cdk/Dockerfile .
#Lauch using docker run -it --rm -v $(pwd):/workspace -w /workspace/cdk aws-bootstrap
```

Image cài đặt:
- **Node.js 24** (từ image gốc) — CDK và build Lambda cần.
- **AWS CLI v2** — cho `aws sts`, `aws s3api`, `aws ecs` và mọi lệnh API AWS khác.
- **AWS CDK CLI** — cho `cdk synth`, `cdk diff`, `cdk deploy`, `cdk destroy`.
- **git, curl, unzip** — CDK asset staging và script dùng.

Không có credentials AWS nào được nướng vào image. Nhóm xác thực sau khi khởi động container.

## Build image sandbox

Từ gốc repository:

```bash
docker build -t aws-bootstrap -f cdk/Dockerfile .
```

Chỉ cần làm một lần. Build lại nếu `Dockerfile.ci-utils` hoặc `cdk/Dockerfile` thay đổi.

## Chạy sandbox

```bash
docker run -it --rm -v $(pwd):/workspace -w /workspace/cdk aws-bootstrap
```

Giải thích cờ:

| Cờ | Mục đích |
|---|---|
| `-it` | Terminal tương tác |
| `--rm` | Xóa container khi thoát |
| `-v $(pwd):/workspace` | Mount repository vào container |
| `-w /workspace/cdk` | Bắt đầu trong thư mục CDK |

## Xác thực bên trong container

Container khởi động mà không có credentials AWS. Đăng nhập từ bên trong:

```bash
aws login
```

Lệnh mở phiên trình duyệt trên máy host. Sau khi xác thực, credentials tạm thời chỉ tồn tại trong container. Khi container thoát, phiên biến mất.

Thiết kế này là có chủ đích. Container không mount `~/.aws` từ host, nên:

- Profile AWS và phiên SSO của host không hiển thị trong container.
- Credentials tạm thời trong container không lưu lại trên host sau khi thoát.
- Các thành viên nhóm khác nhau có thể đăng nhập bằng tài khoản riêng mà không xung đột profile.

## Chạy lệnh CDK

Khi đã xác thực trong sandbox, nhóm có thể chạy bất kỳ lệnh CDK hoặc AWS CLI nào:

```bash
# Tổng hợp template CloudFormation
npx cdk synth --no-strict

# Xem trước thay đổi
npx cdk diff

# Triển khai stack
npx cdk deploy AwsplaceStack --require-approval never --no-strict --import-existing-resources

# Xóa stack
npx cdk destroy AwsplaceStack
```

Tất cả lệnh chạy trong `ap-southeast-1` theo mặc định (đặt trong `awsplace/cdk/bin/app.ts`).

## Trường hợp nghiên cứu: Ước tính billing AWS bị lỗi (16–18 tháng 7 năm 2026)

Ngày 16 tháng 7 năm 2026, AWS gặp sự cố dịch vụ khiến dashboard ước tính billing hiển thị số liệu sai lệch nghiêm trọng. Stack awsplace hiện thị hóa đơn ước tính **$1,174,198,467.12** — rõ ràng là lỗi tính toán, không phải phí thực tế.

![AWS estimated billing showing $1.17B due to a calculation glitch](/images/5-Workshop/5.2-Prerequisite/buggyaws.png)

Nhóm dùng sandbox CLI để xóa stack an toàn mà không ảnh hưởng đến dự án hoặc profile AWS khác trên máy host. Chạy `cdk destroy` trong container đảm bảo thao tác được cách ly và credentials `~/.aws` của host không liên quan.

![cdk destroy running inside the sandbox container](/images/5-Workshop/5.2-Prerequisite/destroy.png)

Lệnh xóa thành công, và ước tính billing bị lỗi được xóa khi tài nguyên stack được gỡ bỏ.

## Thực hành tốt nhất

Luôn dùng sandbox cho bất kỳ thao tác CDK hoặc AWS CLI nào trên stack awsplace:

| Thao tác | Chạy trong sandbox? |
|---|---|
| `cdk diff` | Có |
| `cdk deploy` | Có |
| `cdk destroy` | Có |
| `aws sts get-caller-identity` | Có |
| `aws s3api head-bucket` | Có |
| `aws ecs update-service` | Có |
| `npx cdk bootstrap` | Có |

Chạy những lệnh này trực tiếp trên host có nguy cơ sai phiên bản, rò rỉ credentials và thao tác nhầm profile AWS. Sandbox loại bỏ những rủi ro này với chi phí build Docker một lần.