---
title: "Phần mềm"
date: 2026-07-27
weight: 1
chapter: false
pre: " <b> 5.2.1 </b> "
---

Pipeline sử dụng kết hợp các job dựa trên Docker và shell. Nhóm cần cài đặt các công cụ dưới đây trên máy trạm dùng để kiểm tra repository, cấu hình AWS và gỡ lỗi pipeline.

## Công cụ phát triển

Đây là các ngôn ngữ và runtime mà ứng dụng sử dụng trực tiếp:

| Công cụ | Phiên bản cần thiết | Kiểm tra bằng | Lý do cần thiết |
|---|---|---|---|
| Docker Engine | Bất kỳ bản phát hành hiện tại nào chạy được `docker build` | `docker --version` | Build image Go ECS, image Lambda và image RaftDB (`awsplace/raftdb/Dockerfile`, `awsplace/go-ecs/Dockerfile`, `awsplace/Dockerfile`) |
| Docker Compose | v2, gọi bằng `docker compose` | `docker compose version` | Khởi động MiniStack cục bộ, Go server, nginx và RaftDB sidecar (`awsplace/docker-compose.yml`, `awsplace/docker-compose.ministack.yml`) |
| Go | 1.25 hoặc mới hơn | `go version` | `awsplace/go-ecs/go.mod` khai báo `go 1.25.0`; image CI cài đặt `go1.25.0` |
| Node.js | 24 hoặc mới hơn | `node --version` | `awsplace/lambda/package.json` yêu cầu `>=24.0.0`; image CI là `node:24-bookworm` |
| npm | Đi kèm Node 24 | `npm --version` | Cài đặt CDK và các dependency Lambda |
| Python | 3.12 | `python3 --version` | Canvas exporter trong `awsplace/export/` và tạo báo cáo PDF |
| git | Bất kỳ bản phát hành hiện tại nào | `git --version` | Tag image là commit SHA |

## Công cụ CI/CD pipeline

Các công cụ này được GitLab runner sử dụng và nhóm cũng dùng khi gỡ lỗi pipeline:

| Công cụ | Phiên bản cần thiết | Kiểm tra bằng | Lý do cần thiết |
|---|---|---|---|
| AWS CLI | v2 | `aws --version` | `awsplace/Dockerfile.ci-utils` cài đặt AWS CLI v2 chính thức; dùng cho OIDC exchange, ECR, ECS, CloudFormation, Amplify, S3, Route 53 |
| AWS CDK CLI | v2 | `npx cdk --version` | `awsplace/Dockerfile.ci-utils` cài đặt `aws-cdk` toàn cục; tổng hợp template CloudFormation |
| jq | Bất kỳ bản phát hành hiện tại nào | `jq --version` | Đọc output stack, phân tích file evidence và trích xuất digest image RaftDB |
| zip và unzip | Bất kỳ bản phát hành hiện tại nào | `zip --version` | Triển khai asset Amplify upload `dist/` dưới dạng file zip |
| curl | Bất kỳ bản phát hành hiện tại nào | `curl --version` | Upload frontend zip lên URL S3 presigned bằng `curl --upload-file` |

## Toolchain C++ (tùy chọn)

| Công cụ | Phiên bản cần thiết | Kiểm tra bằng | Lý do cần thiết |
|---|---|---|---|
| CMake | 3.28 hoặc mới hơn | `cmake --version` | `awsplace/raftdb/CMakeLists.txt` yêu cầu `cmake_minimum_required(VERSION 3.28)` |
| Ninja | Bất kỳ bản phát hành hiện tại nào | `ninja --version` | Năm preset CMake trong `awsplace/raftdb/` sử dụng Ninja làm generator |
| Trình biên dịch C++23 | g++ hoặc clang++ hỗ trợ đầy đủ C++23 | `g++ --version` | `awsplace/raftdb/CMakeLists.txt` đặt `CMAKE_CXX_STANDARD 23` với `CMAKE_CXX_EXTENSIONS OFF` |

CMake, Ninja và trình biên dịch C++23 chỉ cần thiết khi nhóm build RaftDB hoặc chạy bộ test C++ trực tiếp trên máy. Quá trình build Docker image trong phần 5.5 tự mang toolchain bên trong `awsplace/raftdb/Dockerfile`, nên nếu chỉ dùng Docker thì bỏ qua ba công cụ này.

## Image `ci-utils`

Giai đoạn deploy của GitLab chạy bên trong image tùy chỉnh được định nghĩa trong `awsplace/Dockerfile.ci-utils`. Image này được build một lần, gắn tag với commit SHA và `main`, sau đó đẩy lên GitLab Container Registry. Image chứa Node.js 24, Go 1.25, AWS CLI v2, Docker CLI, jq, zip, unzip và curl. Image được build lại tự động khi `Dockerfile.ci-utils` hoặc `.gitlab-ci.yml` thay đổi.

Nhóm không cần build image này thủ công, nhưng máy trạm dùng để gỡ lỗi nên cài đặt các công cụ tương tự để có thể chạy lại lệnh cục bộ.

## Kiểm tra nhanh

Chạy đoạn lệnh này để kiểm tra các công cụ bắt buộc. Mỗi dòng nên in ra phiên bản hoặc phản hồi hợp lệ.

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

Nếu nhóm dự định build RaftDB ngoài Docker, chạy thêm:

```bash
cmake --version
ninja --version
g++ --version
```