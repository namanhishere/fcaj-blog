---
title: "Worklog Tuần 1"
date: 2026-06-15
weight: 1
chapter: false
pre: " <b> 1.1. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 1:

* Hoàn tất onboarding và dựng một môi trường làm việc AWS có thể triển khai được, ghim vào một region duy nhất.
* Hiểu bài toán r/place đủ sâu để chốt định dạng lưu trữ canvas trước khi viết server.
* Đăng ký ứng dụng Discord sẽ đảm nhiệm phần xác thực về sau, với phạm vi quyền nhỏ nhất còn dùng được.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Đọc quy định thực tập và mẫu báo cáo <br> - Tạo tài khoản AWS và chọn ap-southeast-1 làm region làm việc duy nhất <br> - Cài và cấu hình AWS CLI, sau đó xác nhận principal bằng aws sts get-caller-identity | 15/06/2026 | 15/06/2026 | <https://cloudjourney.awsstudygroup.com/> <br> <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html> <br> <https://docs.aws.amazon.com/cli/latest/reference/sts/get-caller-identity.html> |
| 3   | - Đọc bài toán r/place: một lưới chung, hàng nghìn người ghi, mọi người đọc đều phải thấy cùng một bảng <br> - **Chốt phạm vi:** <br>&emsp; + một server Go sở hữu buffer canvas và phần phát tán realtime <br>&emsp; + Discord là nhà cung cấp danh tính duy nhất <br>&emsp; + store nhân bản sẽ chọn sau, nên định dạng truyền trên đường truyền không được phụ thuộc vào nó | 16/06/2026 | 16/06/2026 | <https://www.redditinc.com/blog/how-we-built-rplace> |
| 4   | - Tạo ứng dụng Discord trong Developer Portal <br> - Sao chép client id và secret vào DISCORD_CLIENT_ID và DISCORD_CLIENT_SECRET <br> - Đăng ký redirect URI khớp chính xác với DISCORD_REDIRECT_URI, http://localhost:8980/auth/callback cho môi trường cục bộ <br> - Chỉ yêu cầu scope identify, không gì khác <br> - Đặt Discord user id của tôi vào ADMIN_DISCORD_IDS | 17/06/2026 | 17/06/2026 | <https://discord.com/developers/docs/topics/oauth2> |
| 5   | - Thiết kế cách mã hoá canvas: 4 bit cho mỗi pixel, 2 pixel trong một byte, nibble cao trước <br> - **Chốt phép tính chỉ số:** <br>&emsp; + pixelIndex = y * width + x <br>&emsp; + byteIndex = pixelIndex dịch phải một bit <br>&emsp; + pixelIndex chẵn dùng nibble cao, pixelIndex lẻ dùng nibble thấp <br> - Dành riêng chỉ số màu 15 cho ô trống, nên buffer mới có giá trị 0xFF ở mọi byte | 18/06/2026 | 18/06/2026 | <https://go.dev/ref/spec#Arithmetic_operators> <br> <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Bitwise_AND> |
| 6   | - Viết bản cài đặt tham chiếu bằng Go trong go-ecs/internal/canvas/nibble.go <br> - Chuyển đúng phép tính đó sang JavaScript cho bộ kiểm tra tương đương lambda/tests/nibble-parity.js <br> - Phủ kiểm thử cả hai chiều bằng nibble_test.go và canvas_test.go <br> - Ghi lại quy tắc: kích thước bảng luôn đọc lúc chạy, không bao giờ đặt giá trị mặc định trong code | 19/06/2026 | 19/06/2026 | <https://pkg.go.dev/testing> |

Cách mã hoá đủ nhỏ để đọc hết trong một màn hình, và đó chính là chủ ý. `ReadNibble` cùng `WriteNibble` trong `go-ecs/internal/canvas/nibble.go` là bản tham chiếu mà mọi ngôn ngữ khác sao lại:

```go
// go-ecs/internal/canvas/nibble.go
// 4bpp nibble packing. 2 pixels per byte, high nibble first (even pixelIndex).
// Default fill is 0xFF per byte, so both nibbles read back as 15 = empty.

func ReadNibble(buf []byte, pixelIndex int) byte {
	byteIndex := pixelIndex >> 1
	isHigh := (pixelIndex & 1) == 0
	b := buf[byteIndex]
	if isHigh {
		return (b >> 4) & 0xF
	}
	return b & 0xF
}

func WriteNibble(buf []byte, pixelIndex int, color byte) {
	byteIndex := pixelIndex >> 1
	isHigh := (pixelIndex & 1) == 0
	currentByte := buf[byteIndex]
	var newByte byte
	if isHigh {
		newByte = (currentByte & 0x0F) | ((color & 0xF) << 4)
	} else {
		newByte = (currentByte & 0xF0) | (color & 0xF)
	}
	buf[byteIndex] = newByte
}
```

### Kết quả đạt được tuần 1:

* Tài khoản AWS đã hoạt động và mọi tài nguyên tôi tạo từ đây đều nằm trong ap-southeast-1. CLI đã được cấu hình và `aws sts get-caller-identity` trả về đúng principal tôi mong đợi, đây là bước kiểm tra duy nhất tôi tin trước khi chạy bất kỳ câu lệnh triển khai nào.

* Cách mã hoá canvas đã được chốt và ghi lại: 4 bit cho mỗi pixel, 2 pixel trong một byte, nibble cao trước, `pixelIndex = y * width + x`, `byteIndex = pixelIndex >> 1`, và chỉ số màu 15 dành riêng cho ô trống nên bảng chưa vẽ có giá trị 0xFF ở mọi byte. `BufferBytesFor(width, height)` làm tròn lên `width * height * 4` bit thành số byte nguyên, còn `NewCanvasBuffer` lấp toàn bộ vùng cấp phát bằng 0xFF thay vì để giá trị không.

* Tôi nhận thêm một ràng buộc đi kèm cách mã hoá này, và đó là ràng buộc sẽ tốn công nhất về sau: cách đóng gói phải giữ **giống nhau từng byte giữa Go, JavaScript, Python và C++**. Go sở hữu canvas trong `go-ecs/internal/canvas/`, client trên trình duyệt giải mã đúng buffer nó nhận được lúc kết nối, công cụ export đọc buffer đó từ Python, và engine lưu trữ tôi dự định viết sẽ giữ nó trong C++. Bốn bản cài đặt cho cùng bốn dòng phép tính bit là một chi phí bảo trì thật. Tôi chọn nó thay vì một byte cho mỗi pixel vì 8 bit trên mỗi pixel làm tăng gấp đôi kích thước gói dữ liệu toàn bảng mà mọi client mới phải tải, và gói đó là thứ lớn nhất server gửi đi.

* Vì ràng buộc này không thể được hệ thống kiểu của bất kỳ ngôn ngữ nào bảo đảm xuyên qua bốn bản cài đặt, nó phải được bảo đảm bằng kiểm thử. Tuần này nghĩa là các test Go trong `go-ecs/internal/canvas/nibble_test.go` và bộ kiểm tra JavaScript `lambda/tests/nibble-parity.js`, hai bên trao đổi thao tác qua `go_to_js_parity.json` và `js_to_go_parity.json` rồi so sánh buffer thu được. Python và C++ chưa nằm trong bộ kiểm tra này; chúng sẽ tham gia khi công cụ export và store ra đời.

* Ứng dụng Discord đã tồn tại và chỉ yêu cầu scope `identify`. Không có gì về guild, không có gì về tin nhắn. Một lần đặt pixel cần quy được về một user id ổn định và cooldown cần khoá theo id đó, `identify` là đủ cho cả hai.

* Có một quy tắc sinh ra từ việc đọc bài toán chứ không từ việc đọc code, và giờ nó đã được ghi vào quy ước: kích thước bảng là động và được đọc lúc chạy từ config store. Không hằng số, không giá trị mặc định, không hard-code 1000. Việc mở rộng bảng ở tuần sau sẽ nới buffer, và bất kỳ kích thước bị cache lại đều âm thầm làm sai phép tính chỉ số ở trên.
