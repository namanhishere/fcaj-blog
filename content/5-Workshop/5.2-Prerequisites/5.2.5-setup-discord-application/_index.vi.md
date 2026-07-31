---
title: "Thiết lập ứng dụng Discord"
date: 2026-07-27
weight: 5
chapter: false
pre: " <b> 5.2.5 </b> "
---

Ai cũng có thể xem canvas, nhưng đặt pixel yêu cầu đăng nhập Discord. Do đó ứng dụng OAuth là điều kiện bắt buộc, không phải tùy chọn.

## Bước 1: Tạo ứng dụng

1. Mở [Discord Developer Portal](https://discord.com/developers/applications).
2. Nhấn **New Application**.
3. Đặt tên `place` hoặc tên nhóm muốn. Screenshot trong workshop này dùng `place`.

## Bước 2: Copy Client ID và Client Secret

1. Trong ứng dụng, vào **OAuth2** → **General**.
2. Copy **Client ID**. Workshop này dùng `1510122461088448633`.
3. Nhấn **Reset Secret** để hiển thị **Client Secret** nếu nhóm chưa tạo.
4. Copy secret và lưu ngay lập tức. Nó chỉ hiển thị một lần.


## Bước 3: Cấu hình redirect URI

Discord yêu cầu redirect URI khớp chính xác, từng ký tự, bao gồm scheme và dấu gạch chéo cuối. Thêm ba URI này:

| URI | Mục đích |
|---|---|
| `https://place.namanhishere.com/auth/callback` | OAuth callback cho frontend trên Amplify |
| `https://api.place.namanhishere.com/auth/callback` | OAuth callback cho API trên Lambda |
| `http://localhost:8980/auth/callback` | Phát triển cục bộ với Go server |

Screenshot dưới đây hiển thị trang Discord OAuth2 với hai redirect URI production đã điền.

![Discord OAuth2 configuration](/images/5-Workshop/5.2-Prerequisite/discord_oauth.png)

## Bước 4: Chọn scope `identify`

Ứng dụng chỉ cần biết Discord user ID. Yêu cầu scope `identify` mà thôi. Không yêu cầu `email`, `guilds`, `connections` hay scope khác. Screenshot ở trên chỉ chọn `identify`.

## Bước 5: Tìm Discord user ID

1. Trong Discord, bật Developer Mode trong **Settings** → **Advanced** → **Developer Mode**.
2. Nhấp chuột phải vào tên người dùng và chọn **Copy User ID**.
3. Dán giá trị này vào biến `ADMIN_DISCORD_IDS`. Phân cách nhiều admin bằng dấu phẩy.

## Bước 6: Lưu giá trị

Kết thúc phần này, nhóm cần có:

| Giá trị | Nơi lưu |
|---|---|
| Client ID | Biến GitLab CI/CD `DISCORD_CLIENT_ID` |
| Client Secret | Biến GitLab CI/CD `DISCORD_CLIENT_SECRET` |
| Redirect URI | Biến GitLab CI/CD `DISCORD_REDIRECT_URI` và cài đặt app Discord |
| Discord user ID | Biến GitLab CI/CD `ADMIN_DISCORD_IDS` |