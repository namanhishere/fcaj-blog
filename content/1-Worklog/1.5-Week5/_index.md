---
title: "Week 5 Worklog"
date: 2026-07-13
weight: 5
chapter: false
pre: " <b> 1.5. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 5 Objectives:

* Stand up the C++23 build for RaftDB so that a sanitizer run and a release build are each one command.
* Write the Raft node: three roles, a randomised election timeout, and a term that cannot advance in memory before it is on disk.
* Make the log durable on its own terms, with a checksum on every record and a compaction path that never edits a file another reader is using.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Pin the toolchain in CMakeLists.txt: CMake 3.28 minimum, CMAKE_CXX_STANDARD 23, CMAKE_CXX_STANDARD_REQUIRED ON, CMAKE_CXX_EXTENSIONS OFF <br> - **Write the presets in CMakePresets.json:** <br>&emsp; + a hidden base preset that supplies the Ninja generator and the C++23 setting <br>&emsp; + asan, ubsan and tsan as Debug builds, each with its own binary directory <br>&emsp; + release at -O2 with NDEBUG defined <br>&emsp; + fuzz for libFuzzer, which sets RAFTDB_FUZZER ON and adds no compiler flags of its own <br> - Fetch GoogleTest with FetchContent pinned to tag v1.15.2 instead of trusting whatever the host provides | 13/07/2026 | 13/07/2026 | <https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html> <br> <https://google.github.io/googletest/> <br> <https://clang.llvm.org/docs/AddressSanitizer.html> |
| 3   | - Implement the consensus node in src/raft/node.cpp around three roles: kFollower, kCandidate, kLeader <br> - **Count time in ticks rather than milliseconds, so a simulated run and a real one behave identically:** <br>&emsp; + min_election_ticks 10 and max_election_ticks 20 <br>&emsp; + heartbeat_interval_ticks 3 <br>&emsp; + a fresh election deadline drawn per term from a seeded XorShift64 generator <br> - Route every change of term, vote and commit index through update_hard_state, which writes to the hard state store before touching memory and calls fail_stop if that write fails <br> - Guard term increment against overflow instead of letting it wrap | 14/07/2026 | 14/07/2026 | <https://raft.github.io/raft.pdf> <br> <https://raft.github.io/> |
| 4   | - Write the segmented append-only WAL in src/log/log.cpp, default segment size 16 MiB <br> - **Fix the on-disk record layout:** <br>&emsp; + a 21-byte header <br>&emsp; + the payload, capped at 64 MiB <br>&emsp; + a 4-byte CRC32 written little-endian <br> - Use the reflected IEEE 802.3 polynomial 0xEDB88320 so the checksum is byte-identical to the one zlib produces <br> - Call fdatasync on the segment after every record, and fsync the containing directory whenever a new segment file appears | 15/07/2026 | 15/07/2026 | <https://man7.org/linux/man-pages/man2/fdatasync.2.html> <br> <https://www.zlib.net/manual.html> |
| 5   | - Implement generation-based compaction rather than in-place rewriting <br> - **Split it into three functions:** <br>&emsp; + build_generation writes an entire new generation into a hidden temporary directory <br>&emsp; + publish_generation persists the manifest first, then swaps the in-memory state <br>&emsp; + cleanup_generation removes the superseded directory and is allowed to fail quietly, because the committed manifest no longer references it <br> - Point truncate_suffix, truncate_prefix and reset_to_prefix at that same pair so every rewrite takes the same path <br> - **Poison the log on any durability failure,** so the next call throws instead of continuing on a log I can no longer vouch for | 16/07/2026 | 16/07/2026 | <https://man7.org/linux/man-pages/man2/rename.2.html> <br> <https://raft.github.io/raft.pdf> |
| 6   | - Implement the command engine in src/engine/commands.cpp as one switch over net::OpCode with 18 cases, each recovering its typed request out of a variant <br> - **Cover the families the canvas and its history need:** <br>&emsp; + strings GET, SET, EXISTS, DEL, SET..EX..NX, TTL, PREFIX_SCAN <br>&emsp; + hashes HGETALL, HSET, HDEL <br>&emsp; + streams XADD, XRANGE, XREVRANGE, XDEL, XLEN <br>&emsp; + the canvas write BITFIELD_SET_U4 and the compound write PLACE_PIXEL <br> - Register the deterministic simulator as the ctest case raft_sim_seed_smoke, running raft_sim over the seed range 1..10 <br> - Register the linearizability checker twice: lin_check_valid on valid_history.json, and lin_check_invalid on nonlinearizable.json with WILL_FAIL TRUE | 17/07/2026 | 17/07/2026 | <https://redis.io/docs/latest/commands/> <br> <https://jepsen.io/consistency/models/linearizable> <br> <https://cmake.org/cmake/help/latest/manual/ctest.1.html> |

The rule I care most about in the node is that no term or vote reaches memory before it reaches disk. `become_candidate` in `raftdb/src/raft/node.cpp:683-702` shows the shape every state change follows: persist, and give up if the persist failed.

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

The log has the same bias. A record is not appended until its bytes, its checksum and, for a brand new segment, its directory entry have all been forced to disk (`raftdb/src/log/log.cpp:506-519`):

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

### Week 5 Achievements:

* RaftDB builds from a single set of presets. `CMakePresets.json` carries five presets I invoke by name, `asan`, `ubsan`, `tsan`, `release` and `fuzz`, plus a hidden `base` preset that they all inherit for the Ninja generator and `CMAKE_CXX_STANDARD 23`. Each one writes to its own directory under `build/`, which is the point: switching from an AddressSanitizer run to a ThreadSanitizer run does not invalidate the other tree. The cost is five build directories of object files for one project, and I accepted it because the alternative is recompiling the world every time I change sanitizer.

* `CMAKE_CXX_EXTENSIONS OFF` is set deliberately alongside `CMAKE_CXX_STANDARD 23`. Standard C++23 and GNU C++23 are not the same language, and I would rather find out at compile time on my machine than in the container build later.

* The Raft node persists before it mutates, everywhere. Every term bump, vote and commit-index advance goes through `update_hard_state`, which writes to the hard state store and returns false on failure; the caller then abandons the transition rather than proceeding with a state that only exists in memory. When the log detects something worse, a request to truncate an entry that was already committed, it calls `fail_stop` instead of doing the truncation. Stopping is the correct behaviour for a store whose whole purpose is agreeing with its own history, and it is also the expensive one: a node that fail-stops needs an operator, and with one voter in production that means downtime rather than a failover.

* Election timing is deterministic and reproducible. The election deadline is drawn per term from a private `XorShift64` generator seeded from `NodeConfig::seed`, and the timeouts are tick counts, `10` to `20` for elections and `3` for heartbeats, not wall-clock durations. That is what lets the simulator replay an identical run from a seed. It also means none of those three numbers is a latency figure, and I have not converted them into one anywhere.

* Every WAL record is self-checking. The layout is a 21-byte header, then the payload, then a 4-byte CRC32 over both, using the reflected IEEE 802.3 polynomial `0xEDB88320` so that the value matches what zlib would compute over the same bytes. `fdatasync` follows each record, and a newly created segment also triggers an `fsync` of its directory, because a file whose data is durable but whose directory entry is not is a file that can vanish on the next boot.

* Compaction never edits a file in place. `build_generation` writes a complete new generation into a hidden temporary directory, `publish_generation` commits the manifest before swapping any in-memory state, and only then does `cleanup_generation` delete the old directory. A crash halfway through leaves the previous generation authoritative and the new one as garbage that `cleanup_orphans` sweeps later. The three rewriting operations, `truncate_suffix`, `truncate_prefix` and `reset_to_prefix`, all funnel through the same pair, so there is one compaction path to reason about rather than three.

* On top of that, the log refuses to limp. Any durability failure sets a poison flag, after which operations throw with the message about the log owner being poisoned by a durability failure. I preferred an obvious hard stop to a store that keeps answering from a log it cannot guarantee.

* The tests assert correctness properties, not speed. `raft_sim_seed_smoke` runs the deterministic simulator over the seed range `1..10`. Two of the registered cases are negative and carry `WILL_FAIL TRUE`: `raft_sim_bug`, which is the same simulator compiled with `RAFT_INJECT_BUG=1`, and `lin_check_invalid`, which runs the linearizability checker against a history fixture that is deliberately not linearizable. Those two are what stop the suite from passing vacuously, because a checker that never fails is not a checker. GoogleTest cases are discovered by glob and registered with `gtest_discover_tests`, so no total count is written down in the build files, and I am not going to quote one. I also did not measure throughput or latency this week; nothing in the RaftDB tree records a performance number, and inventing one would be worse than leaving the gap visible.

* One capability exists but is not exercised. Joint-consensus membership change is implemented in the node, and the peer transport reserves TCP `9101` for it, but that port stays disabled until the multi-voter phase, so nothing in this week's work replicates to a second member yet. A three-voter cluster is the documented target in the disposable staging stack, not what the application stack runs. Integration with the Go server is next week's work; until then RaftDB is a store I can test but nothing writes to it.
