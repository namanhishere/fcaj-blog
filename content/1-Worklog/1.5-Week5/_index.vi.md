---
title: "Worklog Tuần 5"
date: 2026-07-13
weight: 5
chapter: false
pre: " <b> 1.5. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 5:

* Dựng hệ thống build C++23 cho RaftDB sao cho một lần chạy sanitizer và một bản build release mỗi thứ chỉ cần một câu lệnh.
* Viết phần nhân Raft: ba vai trò, thời gian chờ bầu cử được lấy ngẫu nhiên, và một term không được phép thay đổi trong bộ nhớ trước khi đã nằm trên đĩa.
* Làm cho log tự bảo đảm độ bền của chính nó, với một checksum trên mỗi bản ghi và một đường nén không bao giờ sửa file mà người đọc khác đang dùng.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Ghim toolchain trong CMakeLists.txt: CMake tối thiểu 3.28, CMAKE_CXX_STANDARD 23, CMAKE_CXX_STANDARD_REQUIRED ON, CMAKE_CXX_EXTENSIONS OFF <br> - **Viết các preset trong CMakePresets.json:** <br>&emsp; + một preset base ẩn cung cấp generator Ninja và thiết lập C++23 <br>&emsp; + asan, ubsan và tsan là các bản build Debug, mỗi bản có thư mục binary riêng <br>&emsp; + release ở mức -O2 với NDEBUG được định nghĩa <br>&emsp; + fuzz cho libFuzzer, đặt RAFTDB_FUZZER ON và không thêm cờ biên dịch riêng nào <br> - Lấy GoogleTest bằng FetchContent ghim vào tag v1.15.2 thay vì tin vào bản có sẵn trên máy chủ | 13/07/2026 | 13/07/2026 | <https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html> <br> <https://google.github.io/googletest/> <br> <https://clang.llvm.org/docs/AddressSanitizer.html> |
| 3   | - Cài đặt node đồng thuận trong src/raft/node.cpp quanh ba vai trò: kFollower, kCandidate, kLeader <br> - **Đếm thời gian bằng tick chứ không bằng milisecond, để một lần chạy mô phỏng và một lần chạy thật hành xử giống nhau:** <br>&emsp; + min_election_ticks 10 và max_election_ticks 20 <br>&emsp; + heartbeat_interval_ticks 3 <br>&emsp; + một mốc bầu cử mới được rút cho từng term từ bộ sinh số XorShift64 có seed <br> - Đưa mọi thay đổi của term, phiếu bầu và commit index qua update_hard_state, hàm này ghi vào hard state store trước khi chạm vào bộ nhớ và gọi fail_stop nếu lần ghi đó thất bại <br> - Chặn tràn số khi tăng term thay vì để nó quay vòng | 14/07/2026 | 14/07/2026 | <https://raft.github.io/raft.pdf> <br> <https://raft.github.io/> |
| 4   | - Viết WAL phân đoạn chỉ ghi thêm trong src/log/log.cpp, kích thước phân đoạn mặc định 16 MiB <br> - **Chốt cách trình bày bản ghi trên đĩa:** <br>&emsp; + một header 21 byte <br>&emsp; + phần payload, giới hạn ở 64 MiB <br>&emsp; + một CRC32 4 byte ghi theo little-endian <br> - Dùng đa thức IEEE 802.3 dạng phản chiếu 0xEDB88320 để checksum giống hệt từng byte với giá trị zlib sinh ra <br> - Gọi fdatasync trên phân đoạn sau mỗi bản ghi, và fsync thư mục chứa nó mỗi khi có file phân đoạn mới xuất hiện | 15/07/2026 | 15/07/2026 | <https://man7.org/linux/man-pages/man2/fdatasync.2.html> <br> <https://www.zlib.net/manual.html> |
| 5   | - Cài đặt phép nén theo generation thay vì ghi lại tại chỗ <br> - **Chia thành ba hàm:** <br>&emsp; + build_generation ghi toàn bộ một generation mới vào một thư mục tạm ẩn <br>&emsp; + publish_generation ghi bền manifest trước, rồi mới hoán đổi trạng thái trong bộ nhớ <br>&emsp; + cleanup_generation xoá thư mục đã bị thay thế và được phép thất bại im lặng, vì manifest đã commit không còn tham chiếu tới nó <br> - Hướng truncate_suffix, truncate_prefix và reset_to_prefix vào cùng cặp hàm đó để mọi lần ghi lại đều đi một đường <br> - **Đánh dấu log là nhiễm độc khi có bất kỳ lỗi độ bền nào,** để lần gọi sau ném lỗi thay vì tiếp tục trên một log tôi không còn bảo đảm được | 16/07/2026 | 16/07/2026 | <https://man7.org/linux/man-pages/man2/rename.2.html> <br> <https://raft.github.io/raft.pdf> |
| 6   | - Cài đặt command engine trong src/engine/commands.cpp thành một switch trên net::OpCode với 18 nhánh case, mỗi nhánh lấy ra request có kiểu của nó từ một variant <br> - **Phủ các họ lệnh mà canvas và history của nó cần:** <br>&emsp; + chuỗi GET, SET, EXISTS, DEL, SET..EX..NX, TTL, PREFIX_SCAN <br>&emsp; + hash HGETALL, HSET, HDEL <br>&emsp; + stream XADD, XRANGE, XREVRANGE, XDEL, XLEN <br>&emsp; + lệnh ghi canvas BITFIELD_SET_U4 và lệnh ghi ghép PLACE_PIXEL <br> - Đăng ký bộ mô phỏng tất định thành ca ctest raft_sim_seed_smoke, chạy raft_sim trên dải seed 1..10 <br> - Đăng ký bộ kiểm tra tính tuyến tính hoá hai lần: lin_check_valid trên valid_history.json, và lin_check_invalid trên nonlinearizable.json với WILL_FAIL TRUE | 17/07/2026 | 17/07/2026 | <https://redis.io/docs/latest/commands/> <br> <https://jepsen.io/consistency/models/linearizable> <br> <https://cmake.org/cmake/help/latest/manual/ctest.1.html> |

Quy tắc tôi coi trọng nhất trong node là không một term hay phiếu bầu nào tới được bộ nhớ trước khi tới đĩa. `become_candidate` trong `raftdb/src/raft/node.cpp:683-702` cho thấy hình dạng mà mọi thay đổi trạng thái đều tuân theo: ghi bền, và bỏ dở nếu lần ghi đó thất bại.

```cpp
    if (!update_hard_state(HardState{
            .current_term = static_cast<Term>(current_term_ + 1),
            .voted_for = id_,
            .commit_index = commit_index_,
        })) {
        return;
    }

    role_ = Role::kCandidate;
    leader_id_.reset();
    votes_granted_.clear();
    votes_granted_.insert(id_);
    reset_election_timer();

    if (has_vote_quorum()) {
        become_leader();
        return;
    }
    broadcast_request_vote();
}
```

Log cũng thiên về cùng một hướng. Một bản ghi chưa được coi là đã ghi thêm cho đến khi các byte của nó, checksum của nó, và với một phân đoạn hoàn toàn mới là cả mục thư mục của nó, đều đã được đẩy xuống đĩa (`raftdb/src/log/log.cpp:506-519`):

```cpp
        const auto header_bytes = encode_header(header);
        const auto crc_bytes = encode_crc_le(crc_for(header, entry.payload));
        write_all(fd.get(), header_bytes.data(), header_bytes.size(), path);
        if (!entry.payload.empty()) {
            write_all(fd.get(), entry.payload.data(), entry.payload.size(), path);
        }
        write_all(fd.get(), crc_bytes.data(), crc_bytes.size(), path);
        if (::fdatasync(fd.get()) != 0) {
            throw io_error("fdatasync log segment", path);
        }
        if (new_segment) {
            sync_directory(generation_path(generation_));
        }
        persist_manifest(candidate);
```

### Kết quả đạt được tuần 5:

* RaftDB build được từ một bộ preset duy nhất. `CMakePresets.json` mang năm preset tôi gọi theo tên, `asan`, `ubsan`, `tsan`, `release` và `fuzz`, cộng thêm một preset `base` ẩn mà tất cả đều kế thừa để lấy generator Ninja và `CMAKE_CXX_STANDARD 23`. Mỗi preset ghi vào thư mục riêng dưới `build/`, và đó chính là chủ ý: chuyển từ một lần chạy AddressSanitizer sang ThreadSanitizer không làm mất hiệu lực cây build còn lại. Chi phí là năm thư mục build đầy object file cho một dự án, và tôi chấp nhận vì phương án còn lại là biên dịch lại toàn bộ mỗi lần đổi sanitizer.

* `CMAKE_CXX_EXTENSIONS OFF` được đặt có chủ ý cùng với `CMAKE_CXX_STANDARD 23`. C++23 chuẩn và GNU C++23 không phải cùng một ngôn ngữ, và tôi muốn phát hiện điều đó lúc biên dịch trên máy mình hơn là trong bản build container về sau.

* Node Raft ghi bền trước khi thay đổi bộ nhớ, ở mọi chỗ. Mỗi lần tăng term, mỗi phiếu bầu và mỗi lần đẩy commit index đều đi qua `update_hard_state`, hàm này ghi vào hard state store và trả về false khi thất bại; khi đó bên gọi bỏ dở chuyển đổi thay vì tiếp tục với một trạng thái chỉ tồn tại trong bộ nhớ. Khi log phát hiện điều tệ hơn, một yêu cầu cắt bỏ entry đã được commit, nó gọi `fail_stop` thay vì thực hiện việc cắt. Dừng lại là hành vi đúng cho một store mà toàn bộ mục đích là nhất quán với chính lịch sử của nó, và đó cũng là hành vi đắt: một node fail-stop cần người vận hành, và với một voter duy nhất trên production thì điều đó nghĩa là thời gian ngừng hoạt động chứ không phải một lần chuyển đổi dự phòng.

* Thời gian bầu cử là tất định và lặp lại được. Mốc bầu cử được rút cho từng term từ một bộ sinh `XorShift64` riêng, seed lấy từ `NodeConfig::seed`, và các mốc thời gian là số tick, `10` tới `20` cho bầu cử và `3` cho heartbeat, không phải khoảng thời gian theo đồng hồ. Đó là điều cho phép bộ mô phỏng phát lại y hệt một lần chạy từ một seed. Nó cũng có nghĩa là không con số nào trong ba con số đó là một chỉ số độ trễ, và tôi không quy đổi chúng thành độ trễ ở bất cứ đâu.

* Mỗi bản ghi WAL đều tự kiểm tra được. Cách trình bày là một header 21 byte, rồi payload, rồi một CRC32 4 byte tính trên cả hai phần, dùng đa thức IEEE 802.3 dạng phản chiếu `0xEDB88320` để giá trị khớp với những gì zlib sẽ tính trên cùng dãy byte. `fdatasync` chạy sau mỗi bản ghi, và một phân đoạn vừa được tạo còn kéo theo một `fsync` trên thư mục của nó, vì một file có dữ liệu bền nhưng mục thư mục chưa bền là một file có thể biến mất ở lần khởi động sau.

* Phép nén không bao giờ sửa file tại chỗ. `build_generation` ghi trọn một generation mới vào một thư mục tạm ẩn, `publish_generation` commit manifest trước khi hoán đổi bất kỳ trạng thái trong bộ nhớ, và chỉ sau đó `cleanup_generation` mới xoá thư mục cũ. Một lần sập ở giữa quá trình để lại generation trước đó làm nguồn có hiệu lực và generation mới thành rác mà `cleanup_orphans` quét sau. Cả ba thao tác ghi lại, `truncate_suffix`, `truncate_prefix` và `reset_to_prefix`, đều dồn qua cùng cặp hàm đó, nên chỉ có một đường nén cần suy luận thay vì ba.

* Ngoài ra, log không chịu đi khập khiễng. Bất kỳ lỗi độ bền nào cũng đặt một cờ nhiễm độc, sau đó các thao tác ném lỗi kèm thông báo rằng chủ sở hữu log đã bị nhiễm độc bởi một lỗi độ bền. Tôi chọn một lần dừng cứng dễ thấy hơn là một store vẫn tiếp tục trả lời từ một log nó không bảo đảm được.

* Các bài kiểm thử khẳng định các tính chất đúng đắn, không phải tốc độ. `raft_sim_seed_smoke` chạy bộ mô phỏng tất định trên dải seed `1..10`. Hai trong số các ca đã đăng ký là ca âm và mang `WILL_FAIL TRUE`: `raft_sim_bug`, chính là bộ mô phỏng đó biên dịch với `RAFT_INJECT_BUG=1`, và `lin_check_invalid`, chạy bộ kiểm tra tính tuyến tính hoá trên một fixture lịch sử cố tình không tuyến tính hoá được. Hai ca đó là thứ ngăn bộ kiểm thử pass một cách rỗng, vì một bộ kiểm tra không bao giờ báo lỗi thì không phải là bộ kiểm tra. Các ca GoogleTest được tìm bằng glob và đăng ký qua `gtest_discover_tests`, nên không có tổng số nào được ghi trong các file build, và tôi sẽ không nêu ra một con số. Tuần này tôi cũng không đo thông lượng hay độ trễ; không có gì trong cây nguồn RaftDB ghi lại một chỉ số hiệu năng, và tự đặt ra một con số sẽ tệ hơn là để lỗ trống đó lộ ra.

* Có một khả năng đã tồn tại nhưng chưa được dùng tới. Thay đổi thành viên bằng joint consensus đã được cài đặt trong node, và lớp truyền tải giữa các peer dành riêng cổng TCP `9101` cho nó, nhưng cổng đó vẫn bị tắt cho tới giai đoạn nhiều voter, nên chưa có gì trong công việc tuần này nhân bản sang một thành viên thứ hai. Một cụm ba voter là mục tiêu đã được ghi lại trong stack staging dùng một lần, không phải trạng thái mà stack ứng dụng đang chạy. Việc tích hợp với server Go là công việc của tuần sau; cho tới lúc đó RaftDB là một store tôi có thể kiểm thử nhưng chưa có gì ghi vào.
