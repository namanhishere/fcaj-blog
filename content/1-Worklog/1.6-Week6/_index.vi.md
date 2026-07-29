---
title: "Worklog Tuần 6"
date: 2026-07-20
weight: 6
chapter: false
pre: " <b> 1.6. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 6:

* Nối server Go với RaftDB qua giao thức nhị phân, bằng một bộ codec khớp từng byte với phía C++.
* Đưa mọi datastore ra sau một interface Go duy nhất để lựa chọn backend không còn rò rỉ vào code ứng dụng.
* Cấp cho sidecar phần lưu trữ bền: một EFS access point cho write-ahead log, và snapshot định kỳ lên S3.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Chốt cách đóng khung trên đường truyền trong proto/PROTOCOL.md thành giao thức phiên bản 1 <br> - **Cố định khung tin thành bốn trường, length trước tiên:** <br>&emsp; + length, uint32 big-endian, đếm mọi thứ sau chính nó, giá trị nhỏ nhất là 2 <br>&emsp; + version, một byte, hiện là 1, mọi giá trị khác là lỗi giao thức <br>&emsp; + opcode, một byte <br>&emsp; + payload dài length trừ 2 byte <br> - Viết rõ quy tắc cho bên đọc: đóng kết nối khi length nhỏ hơn 2 và khi version không nhận ra <br> - Ghi vào đặc tả rằng các kết nối không được xác thực ở lớp giao thức, và đó là lý do listener chỉ tiếp cận được qua loopback | 20/07/2026 | 20/07/2026 | <https://redis.io/docs/latest/develop/reference/protocol-spec/> |
| 3   | - Viết bộ codec Go trong go-ecs/internal/store/raftdb/proto.go <br> - Chuyển đủ 18 opcode từ đặc tả, gồm BITFIELD_SET_U4 ở 0x04, XADD ở 0x20, SUBSCRIBE ở 0x30 và PLACE_PIXEL ở 0x31 <br> - **Chuyển cả chín byte trạng thái, vì client phải xử lý mỗi loại một cách khác nhau:** <br>&emsp; + StatusOK, StatusNotFound, StatusExists, StatusInvalid <br>&emsp; + StatusNotLeader, byte này mang theo một địa chỉ chuyển hướng <br>&emsp; + StatusReadOnly, StatusEventEnded, StatusBanned, StatusCooldownActive <br> - Giới hạn MaxFrameLen ở 16 MiB phía Go cho khớp ngưỡng khuyến nghị trong đặc tả <br> - Tách ErrNeedMore khỏi lỗi giải mã thật, để một lần đọc dở dang không bao giờ bị hiểu thành khung tin sai | 21/07/2026 | 21/07/2026 | <https://pkg.go.dev/encoding/binary> |
| 4   | - Khai báo lớp trừu tượng lưu trữ trong go-ecs/internal/store/interface.go: DatabaseBackend với 15 phương thức trải trên config, ban, milestone và history <br> - Khai báo AtomicPlacementBackend riêng, với một phương thức duy nhất PlacePixel, để một backend không thể ghi pixel cùng history của nó trong một thao tác thì đơn giản là không cài đặt interface đó <br> - **Gặp và xử lý vòng lặp import trong factory của backend:** <br>&emsp; + store/factory.go nằm trong package store, còn store/postgres và store/filesystem đều import store cho phần khẳng định interface của chúng <br>&emsp; + một factory trong package store mà khởi tạo chúng do đó khép kín vòng lặp <br>&emsp; + chuyển factory sang internal/backends/factory.go, một package không bị ai import ngược lại <br> - Giữ lại store/factory.go kèm ghi chú không dùng nữa thay vì xoá nó trong cùng một lần thay đổi | 22/07/2026 | 22/07/2026 | <https://go.dev/doc/effective_go#interfaces> <br> <https://go.dev/ref/spec#Import_declarations> |
| 5   | - Build image RaftDB qua bốn tầng: aws-sdk-builder và builder trên ubuntu 24.04, go-tools-builder trên golang 1.25-alpine, và một tầng runtime ubuntu 24.04 mới <br> - Ghim aws-sdk-cpp vào commit 0c4942f81092d175da061a05a27df8369f70871f và chỉ build thành phần s3 với MINIMIZE_SIZE ON <br> - **Làm cho tầng runtime không có đặc quyền ngay từ cấu trúc:** <br>&emsp; + tạo group và user 10001 với shell nologin và /data/raftdb làm home directory <br>&emsp; + chown thư mục dữ liệu gốc về 10001:10001, rồi chuyển sang USER 10001:10001 trước entrypoint <br> - Đặt entrypoint là /usr/local/bin/raftdb_server và lệnh health của container là /usr/local/bin/raftdb-healthcheck | 23/07/2026 | 23/07/2026 | <https://docs.docker.com/build/building/multi-stage/> <br> <https://docs.docker.com/build/building/best-practices/> |
| 6   | - Cấp cho sidecar một EFS access point ở /raftdb/production/member-1, tạo với chủ sở hữu 10001:10001 và quyền 0750, rồi mount vào /data/raftdb với mã hoá trên đường truyền và IAM authorization được bật <br> - Tạo bucket snapshot có versioning, có mã hoá, chặn toàn bộ truy cập công khai, bắt buộc SSL ở TLS 1.2, với các phiên bản không hiện hành hết hạn sau 35 ngày <br> - Chỉ cấp cho task role quyền đọc ghi trên prefix production/member-1, không phải toàn bộ bucket <br> - Đặt RAFTDB_SNAPSHOT_INTERVAL_SECONDS là 300 và RAFTDB_SNAPSHOT_PREFIX là production/member-1 trên container <br> - **Viết ra hợp đồng retry của client trước khi có client nào cần tới nó:** <br>&emsp; + một phản hồi NOT_LEADER có thể được theo sau bởi nhiều nhất một lần chuyển hướng tới leader được thông báo <br>&emsp; + một lỗi truyền tải không rõ kết quả có thể được thử lại một lần, dùng chung đúng ngân sách đó, nên một request được gửi nhiều nhất hai lần tổng cộng <br>&emsp; + chỉ một XADD hoặc PLACE_PIXEL có gắn thẻ mới đủ điều kiện; mọi lệnh ghi khác không được thử lại tự động | 24/07/2026 | 24/07/2026 | <https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html> <br> <https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html> <br> <https://docs.aws.amazon.com/sdkref/latest/guide/feature-retry-behavior.html> |

Toàn bộ quy tắc đóng khung gói gọn trong một hàm Go, và viết theo cách này nghĩa là bộ mã hoá không thể lệch khỏi đặc tả một cách tình cờ (`go-ecs/internal/store/raftdb/proto.go:211-220`):

```go
func EncodeFrame(op OpCode, payload []byte) ([]byte, error) {
	if len(payload) > int(MaxFrameLen)-2 {
		return nil, fmt.Errorf("raftdb: payload too large")
	}
	out := make([]byte, 4, 6+len(payload))
	binary.BigEndian.PutUint32(out[:4], uint32(2+len(payload)))
	out = append(out, ProtocolVersion, byte(op))
	out = append(out, payload...)
	return out, nil
}
```

Danh tính của container được quyết trong image, không phải trong task definition, và đó là điều làm cho EFS access point về sau trở nên đơn giản (`raftdb/Dockerfile:87-110`):

```dockerfile
RUN groupadd --gid 10001 raftdb \
    && useradd --uid 10001 --gid 10001 --home-dir /data/raftdb \
        --shell /usr/sbin/nologin raftdb \
    && mkdir -p /data/raftdb \
    && chown -R 10001:10001 /data/raftdb \
    && chmod 0755 /usr/local/bin/raftdb-healthcheck

RUN ldconfig

USER 10001:10001
WORKDIR /data/raftdb

ENV RAFTDB_PORT=9100 \
    RAFTDB_DATA_DIR=/data/raftdb \
    RAFTDB_READY_FILE=/tmp/raftdb-ready \
    RAFTDB_SNAPSHOT_INTERVAL_SECONDS=300

EXPOSE 9100
VOLUME ["/data/raftdb"]

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=10 \
    CMD ["/usr/local/bin/raftdb-healthcheck"]

ENTRYPOINT ["/usr/local/bin/raftdb_server"]
```

### Kết quả đạt được tuần 6:

* Hai bản cài đặt của giao thức khớp nhau vì cả hai được viết từ cùng một tài liệu chứ không phải từ nhau. `raftdb/proto/PROTOCOL.md` là văn bản quy chuẩn: một khung tin gồm `length` dạng uint32 big-endian, rồi một byte version, rồi một byte opcode, rồi payload, với `length` được tính là `2 + len(payload)`. Khối hằng opcode phía Go trong `go-ecs/internal/store/raftdb/proto.go:21-40` mang đúng 18 giá trị như bảng opcode của đặc tả, và chín byte trạng thái cũng khớp. `MaxFrameLen` là `16 * 1024 * 1024`, khớp ngưỡng khuyến nghị trong đặc tả thay vì một con số tôi tự chọn.

* Giao thức không có lớp xác thực, và đặc tả nói thẳng điều đó. Đây là một quyết định thiết kế đi kèm một giới hạn thật: RaftDB chỉ an toàn vì container App tiếp cận nó qua `127.0.0.1:9100` trong cùng một task, và nó không bao giờ được phơi ra ngoài ranh giới đó ở dạng hiện tại. Một bên tiêu thụ thứ hai, ở một task khác hay một service khác, sẽ cần hoặc một proxy đứng trước hoặc một thay đổi trong giao thức. Tôi viết ràng buộc này vào đặc tả thay vì để nó thành lời truyền miệng về việc container tình cờ được triển khai ra sao.

* `PLACE_PIXEL`, opcode `0x31`, là lý do RaftDB tồn tại. Nó mang canvas key, history key, chỉ số pixel, màu bốn bit và bản ghi history trong một request duy nhất, nên lệnh ghi pixel và bản ghi history của nó hoặc cùng xảy ra hoặc cùng không. Phía Go, hình dạng đó là struct `PlacementMutation`. Khả năng này có chủ ý không phải là vô điều kiện: đường đặt pixel chỉ dùng nó khi backend đang cấu hình thoả mãn khẳng định `AtomicPlacementBackend`, còn mọi backend khác lùi về hai lệnh ghi riêng biệt với rủi ro phân kỳ đi kèm.

* Phần lưu trữ nằm sau một interface duy nhất, và kích thước của nó trung thực với bề mặt liên quan: `DatabaseBackend` khai báo 15 phương thức trong bốn nhóm, bốn cho config, bốn cho ban, bốn cho milestone và ba cho history. `AtomicPlacementBackend` là một interface thứ hai chỉ có một phương thức chứ không phải phương thức thứ mười sáu, và chính điều đó cho phép một backend từ chối phần đặt pixel nguyên tử mà không phải viết hàm rỗng cho việc nó không làm được. File `AGENTS.md` của repo vẫn ghi mười sáu; file interface là nguồn có thẩm quyền và nó ghi mười lăm.

* Trở ngại thật của tuần này thuộc về cấu trúc chứ không liên quan gì tới đồng thuận. `store/factory.go` nằm trong package `store`, còn `store/postgres` và `store/filesystem` mỗi package đều import `store` cho phần khẳng định interface, nên một factory bên trong `store` mà khởi tạo các backend đó khép kín một vòng lặp import. Bản ghi trong `awsplace/learnings.md:1-6` nói trực tiếp điều này: các package đó import `store`, và sub-package DynamoDB thoát khỏi vấn đề chỉ vì nó không import. Cách xử lý là chuyển factory ra `internal/backends/factory.go`, một package có thể import mọi bản cài đặt vì không ai import nó ngược lại, và đó chính là package mà backend RaftDB được đăng ký vào. Hai chi phí đi kèm. `store/factory.go` vẫn còn đó, mang một ghi chú không dùng nữa trỏ sang bản thay thế, vì xoá nó trong cùng lần thay đổi sẽ làm diff rộng quá mức tôi có thể tự soát. Và `main.go` cần coi client DynamoDB là tuỳ chọn, với một khẳng định kiểu an toàn khi giá trị nil cùng các đường WebSocket, admin và scheduler được đặt sau một điều kiện, điều mà code trước đó không có.

* Image gồm bốn tầng, và ranh giới giữa các tầng là điều giữ cho phần runtime nhỏ: `aws-sdk-builder` biên dịch aws-sdk-cpp từ một commit đã ghim, `builder` biên dịch `raftdb_server` dựa trên nó, `go-tools-builder` sinh các binary phụ trợ bằng Go với `CGO_ENABLED=0`, và tầng runtime khởi đầu từ một `ubuntu:24.04` sạch rồi chỉ copy vào những gì nó cần. SDK được ghim vào commit `0c4942f81092d175da061a05a27df8369f70871f` với `BUILD_ONLY=s3`, nên một thay đổi ở thượng nguồn không thể làm khác đi các byte của một image build từ commit ứng dụng cũ hơn. Biên dịch SDK đó từ nguồn là cái giá phải trả, và đó là phần chậm nhất của bản build.

* Container không chạy bằng root, tính từ trước khi nó chạy bất cứ thứ gì. Group và user `10001` được tạo trong image, thư mục dữ liệu gốc được chown về chúng, và `USER 10001:10001` đứng trước entrypoint. Đó là điều làm cho EFS access point trở nên đơn giản: nó được tạo với `ownerUid` và `ownerGid` là `10001` cùng quyền `0750`, nên sidecar hạ xuống một thư mục nó đã sở hữu và không cần `chown` nào lúc khởi động trên một filesystem qua mạng. Volume được mount với mã hoá trên đường truyền và IAM authorization được bật, còn quyền EFS của task role là `ClientMount` và `ClientWrite` có điều kiện gắn với đúng ARN của access point đó.

* Snapshot đi tới một bucket có versioning, có mã hoá, chặn truy cập công khai và hạn chế ở TLS 1.2 trở lên, với các phiên bản không hiện hành hết hạn sau 35 ngày. Task role chỉ được cấp quyền đọc ghi trên prefix `production/member-1`. Container công bố snapshot với `RAFTDB_SNAPSHOT_INTERVAL_SECONDS` là `300`, và `RAFTDB_RESTORE_FROM_S3` là `false` trong stack ứng dụng, vì WAL bền trên EFS là nguồn phục hồi chính còn S3 là bản sao ngoài site. Chỉ một bên ghi sở hữu WAL đó, và đây là ràng buộc mà các thiết lập triển khai phải tôn trọng chứ không phải điều store có thể tự phân xử.

* Các quy tắc thử lại đã được viết ra và có chủ ý hẹp. Một phản hồi `NOT_LEADER`, trạng thái `0x04`, có thể được theo sau bởi nhiều nhất một lần chuyển hướng tới leader được thông báo, với payload đã mã hoá và các trường định danh mutation được dùng lại y nguyên chứ không sinh lại; một lỗi truyền tải không rõ kết quả có thể được thử lại một lần và dùng chung đúng ngân sách đó, nên mọi request được gửi nhiều nhất hai lần tổng cộng. Chỉ một `XADD` hoặc `PLACE_PIXEL` có gắn thẻ là đủ điều kiện, vì hai lệnh đó mang một mutation ID 16 byte mà server giữ lại xuyên qua quá trình phát lại WAL và các snapshot. `SET`, `BITFIELD_SET_U4`, `DEL`, `HSET`, `HDEL` và `XDEL` không được thử lại tự động lần nào. Điều đó đẩy phần không rõ ràng trở lại cho bên gọi với phần lớn lệnh ghi, và đây là sự đánh đổi trung thực: tôi muốn bên gọi tự quyết định phải làm gì với một `SET` không rõ kết quả hơn là để client âm thầm gửi nó hai lần.
