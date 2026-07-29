---
title: "Worklog Tuần 2"
date: 2026-06-22
weight: 2
chapter: false
pre: " <b> 1.2. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 2:

* Xây dựng server WebSocket bằng Go: nâng cấp kết nối, sổ đăng ký client, và phát tán tới mọi client đang kết nối.
* Chốt cứng danh sách tên thông điệp realtime để frontend và server được viết theo cùng một giao thức.
* Chạy được toàn bộ stack cục bộ bằng Docker Compose, với bài kiểm tra canvas liên ngôn ngữ vượt qua.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Chọn thư viện WebSocket: coder/websocket v1.8.14 thay vì gorilla/websocket <br> - **Ghi lại các quy ước Go mà quyết định này nằm trong:** <br>&emsp; + không dùng framework router HTTP, chỉ net/http thuần với method routing của Go 1.22+ <br>&emsp; + CGO_ENABLED=0 để có binary tĩnh <br>&emsp; + gofmt là formatter duy nhất, package trong internal/ đặt tên theo miền của nó | 22/06/2026 | 22/06/2026 | <https://pkg.go.dev/github.com/coder/websocket> <br> <https://pkg.go.dev/net/http#ServeMux> |
| 3   | - Viết hub trong go-ecs/internal/ws/hub.go <br> - **Cấu trúc:** <br>&emsp; + một map clients được bảo vệ bằng sync.RWMutex <br>&emsp; + các channel register, unregister và broadcast, riêng channel broadcast có buffer 256 <br>&emsp; + một goroutine duy nhất trong Run sở hữu mọi thay đổi của sổ đăng ký <br> - Viết vòng lặp đọc và ghi cho từng kết nối trong client.go | 23/06/2026 | 23/06/2026 | <https://pkg.go.dev/sync#RWMutex> <br> <https://go.dev/doc/effective_go#channels> |
| 4   | - Chốt giao thức realtime trong protocol.go: tám tên thông điệp, bảy chiều server tới client cộng PLACE_PIXEL từ client <br> - Bọc mọi thông điệp trong một envelope gồm type và payload, giữ payload ở dạng json.RawMessage để các trường số như colorIndex vẫn là số <br> - Định nghĩa payload INIT_DATA: toàn bộ lưới, palette, kích thước và cooldown | 24/06/2026 | 24/06/2026 | <https://datatracker.ietf.org/doc/html/rfc6455> <br> <https://pkg.go.dev/encoding/json#RawMessage> |
| 5   | - Cài đặt kiểm tra origin trong handler.go, trước khi nâng cấp kết nối chứ không phải sau <br> - **Các quy tắc, theo thứ tự:** <br>&emsp; + không có header Origin thì cho phép, vì client không phải trình duyệt không gửi header này <br>&emsp; + Origin có trong ALLOWED_ORIGINS thì cho phép, khớp chính xác hoặc khớp subdomain <br>&emsp; + ALLOWED_ORIGINS rỗng thì chỉ cho phép khi host của origin trùng host của request <br>&emsp; + còn lại thì từ chối với mã 403 <br> - Truyền InsecureSkipVerify cho websocket.Accept vì phần kiểm tra của tôi đã chạy trước đó <br> - Lấy IP client từ mục ngoài cùng bên trái của X-Forwarded-For | 25/06/2026 | 25/06/2026 | <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Origin> <br> <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-For> |
| 6   | - Dựng stack bằng docker compose up --build -d <br> - Xác nhận sơ đồ cổng: server 8980, server thứ hai 8981, nginx 19980, raftdb 9100 <br> - Chạy bài kiểm tra liên ngôn ngữ bằng node lambda/tests/nibble-parity.js <br> - Vẽ từ hai tab trình duyệt và quan sát PIXEL_UPDATE đến ở cả hai | 26/06/2026 | 26/06/2026 | <https://docs.docker.com/compose/> |

Thứ tự của hai lần kiểm tra trong `go-ecs/internal/ws/handler.go` là phần đáng trích dẫn, vì làm ngược lại là giao chính sách origin cho thư viện:

```go
// go-ecs/internal/ws/handler.go
origin := r.Header.Get("Origin")
// net/http promotes Host to Request.Host and removes it from Header,
// so Header.Get("Host") is empty for real requests.
host := r.Host
if !originAllowed(origin, host) {
	http.Error(w, "Origin not allowed", http.StatusForbidden)
	return
}

conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
	// originAllowed above performs the configurable cross-origin check.
	// Disable the library's same-host-only check after that validation.
	InsecureSkipVerify: true,
})
```

Dựng cục bộ chỉ gồm hai câu lệnh, và câu thứ hai mới là câu tôi thật sự ngồi xem:

```bash
docker compose up --build -d
node lambda/tests/nibble-parity.js
```

### Kết quả đạt được tuần 2:

* Một canvas cục bộ chạy được từ đầu đến cuối. `docker compose up --build -d` khởi động raftdb ở cổng 9100, server Go ở 8980, một server Go thứ hai ở 8981, và nginx phục vụ frontend ở 19980. Server chờ healthcheck của raftdb, mà healthcheck đó chỉ là một phép thăm dò TCP trần (`exec 3<>/dev/tcp/127.0.0.1/9100`) chứ không phải một truy vấn, nên thứ tự phụ thuộc là thật nhưng còn nông. Một pixel đặt ở tab trình duyệt này xuất hiện ở tab kia, được chuyển đi dưới dạng phát tán `PIXEL_UPDATE` qua hub.

* `node lambda/tests/nibble-parity.js` vượt qua cả hai vòng. Vòng một đọc `go_to_js_parity.json`, phát lại các thao tác mà test Go đã ghi, rồi đối chiếu chuỗi hex của buffer thu được; vòng hai sinh thao tác ngẫu nhiên mới vào `js_to_go_parity.json` để phía Go phát lại. Đó chính là cơ chế bảo đảm cho ràng buộc giống nhau từng byte mà tôi đã nhận ở tuần 1, và giờ nó đang chạy thật chứ không còn là mong muốn.

* Giao thức realtime được chốt ở tám tên trong `go-ecs/internal/ws/protocol.go`: `INIT_DATA`, `PIXEL_UPDATE`, `BOARD_RESIZE`, `ONLINE_COUNT_UPDATE`, `COOLDOWN_START`, `AUTH_REQUIRED` và `ERROR` từ phía server, cộng thêm `PLACE_PIXEL` từ phía client. Mọi thứ đi trong một envelope với chuỗi `type` và payload dạng `json.RawMessage`, và đó là điều giữ cho `colorIndex` vẫn là một số thay vì bị mã hoá lại thành chuỗi.

* Hub được viết một cách có chủ ý là nhàm chán. Một goroutine `Run` duy nhất tiêu thụ các channel register, unregister và broadcast, nên map clients chỉ bị thay đổi từ đúng một chỗ, và `sync.RWMutex` tồn tại cho những bên đọc như bộ đếm số người đang online chứ không phải để điều phối các bên ghi. Channel broadcast có buffer 256, nghĩa là một đợt dồn lớn hơn con số đó sẽ làm bên gọi phải chờ thay vì bỏ mất cập nhật. Tôi chọn một lần ghi chậm hơn là một pixel âm thầm biến mất.

* Điểm đánh đổi được nêu rõ về origin: khi `ALLOWED_ORIGINS` không được đặt, server rơi về chế độ chỉ cho phép cùng origin. Đó là giá trị mặc định đúng cho môi trường cục bộ, và nó cũng có nghĩa là một frontend đã triển khai nhưng phục vụ từ hostname khác sẽ bị từ chối kết nối cho tới khi biến này được đặt tường minh. `docker-compose.yml` đặt nó thành `http://localhost:19980,http://127.0.0.1:19980` để nginx và server thống nhất với nhau.

* Có hai việc còn dở, và tôi biết rõ. Cooldown khi đặt pixel nằm trong bộ nhớ của tiến trình Go, nên khởi động lại server là người dùng lại đặt được ngay, một điểm hạn chế đã được ghi trong `awsplace/README.md`. Và `AUTH_ENABLED` đang là `false` trong `docker-compose.yml`, nên hiện tại tab nào cũng vẽ được. Đăng nhập Discord trên Lambda là việc của tuần sau, và cho tới khi nó tồn tại thì canvas cục bộ vẫn chỉ là bản demo, chưa phải một hệ thống.
