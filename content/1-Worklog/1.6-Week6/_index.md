---
title: "Week 6 Worklog"
date: 2026-07-20
weight: 6
chapter: false
pre: " <b> 1.6. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 6 Objectives:

* Connect the Go server to RaftDB over the binary protocol, with a codec that agrees with the C++ side byte for byte.
* Put every datastore behind one Go interface so the choice of backend stops leaking into the application code.
* Give the sidecar durable storage: an EFS access point for the write-ahead log, and periodic snapshots to S3.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Freeze the wire framing in proto/PROTOCOL.md as protocol version 1 <br> - **Fix the frame as four fields, length first:** <br>&emsp; + length, uint32 big-endian, counting everything after itself, minimum value 2 <br>&emsp; + version, one byte, currently 1, any other value a protocol error <br>&emsp; + opcode, one byte <br>&emsp; + payload of length minus 2 bytes <br> - Write the reader rules explicitly: close the connection on a length below 2 and on an unknown version <br> - Record in the spec that connections are not authenticated at the protocol layer, which is why the listener is reachable only over loopback | 20/07/2026 | 20/07/2026 | <https://redis.io/docs/latest/develop/reference/protocol-spec/> |
| 3   | - Write the Go codec in go-ecs/internal/store/raftdb/proto.go <br> - Transcribe all 18 opcodes from the spec, including BITFIELD_SET_U4 at 0x04, XADD at 0x20, SUBSCRIBE at 0x30 and PLACE_PIXEL at 0x31 <br> - **Transcribe the nine status bytes too, because the client has to act on them differently:** <br>&emsp; + StatusOK, StatusNotFound, StatusExists, StatusInvalid <br>&emsp; + StatusNotLeader, which carries a redirect address <br>&emsp; + StatusReadOnly, StatusEventEnded, StatusBanned, StatusCooldownActive <br> - Cap MaxFrameLen at 16 MiB on the Go side to match the spec's recommended ceiling <br> - Separate ErrNeedMore from a real decode error so a partial read is never mistaken for a bad frame | 21/07/2026 | 21/07/2026 | <https://pkg.go.dev/encoding/binary> |
| 4   | - Declare the storage abstraction in go-ecs/internal/store/interface.go: DatabaseBackend with 15 methods across config, bans, milestones and history <br> - Declare AtomicPlacementBackend separately, with the single method PlacePixel, so a backend that cannot write a pixel and its history in one operation simply does not implement it <br> - **Hit and fix the import cycle in the backend factory:** <br>&emsp; + store/factory.go lives in package store, and store/postgres and store/filesystem both import store for their interface assertions <br>&emsp; + a factory in package store that constructs them therefore closes the loop <br>&emsp; + move the factory to internal/backends/factory.go, a package nothing imports back <br> - Leave store/factory.go behind with a deprecation notice rather than deleting it in the same change | 22/07/2026 | 22/07/2026 | <https://go.dev/doc/effective_go#interfaces> <br> <https://go.dev/ref/spec#Import_declarations> |
| 5   | - Build the RaftDB image in four stages: aws-sdk-builder and builder on ubuntu 24.04, go-tools-builder on golang 1.25-alpine, and a fresh ubuntu 24.04 runtime <br> - Pin aws-sdk-cpp to commit 0c4942f81092d175da061a05a27df8369f70871f and build only the s3 component with MINIMIZE_SIZE ON <br> - **Make the runtime stage unprivileged by construction:** <br>&emsp; + create group and user 10001 with a nologin shell and /data/raftdb as the home directory <br>&emsp; + chown the data root to 10001:10001, then switch to USER 10001:10001 before the entrypoint <br> - Set the entrypoint to /usr/local/bin/raftdb_server and the container health command to /usr/local/bin/raftdb-healthcheck | 23/07/2026 | 23/07/2026 | <https://docs.docker.com/build/building/multi-stage/> <br> <https://docs.docker.com/build/building/best-practices/> |
| 6   | - Give the sidecar an EFS access point at /raftdb/production/member-1, created with owner 10001:10001 and permissions 0750, and mount it at /data/raftdb with transit encryption and IAM authorization enabled <br> - Create the snapshot bucket versioned, encrypted, public access blocked, SSL enforced at TLS 1.2, with noncurrent versions expiring after 35 days <br> - Grant the task role read and write on the prefix production/member-1 only, not the whole bucket <br> - Set RAFTDB_SNAPSHOT_INTERVAL_SECONDS to 300 and RAFTDB_SNAPSHOT_PREFIX to production/member-1 on the container <br> - **Write the client retry contract down before any client needs it:** <br>&emsp; + a NOT_LEADER reply may be followed by at most one redirect to the advertised leader <br>&emsp; + an ambiguous transport failure may be retried once, sharing that same budget, so a request gets at most two sends in total <br>&emsp; + only a tagged XADD or PLACE_PIXEL qualifies; every other write is not retried automatically | 24/07/2026 | 24/07/2026 | <https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html> <br> <https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html> <br> <https://docs.aws.amazon.com/sdkref/latest/guide/feature-retry-behavior.html> |

The whole framing rule fits in one Go function, and writing it this way meant the encoder could not disagree with the specification by accident (`go-ecs/internal/store/raftdb/proto.go:211-220`):

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

The container's identity is decided in the image, not in the task definition, which is what makes the EFS access point straightforward later (`raftdb/Dockerfile:87-110`):

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

### Week 6 Achievements:

* The two implementations of the protocol agree because they were written from the same document rather than from each other. `raftdb/proto/PROTOCOL.md` is normative: a frame is `length` as a big-endian uint32, then a version byte, then an opcode byte, then the payload, with `length` computed as `2 + len(payload)`. The Go opcode block in `go-ecs/internal/store/raftdb/proto.go:21-40` carries the same 18 values as the spec's opcode table, and the nine status bytes match as well. `MaxFrameLen` is `16 * 1024 * 1024`, matching the recommended ceiling in the spec rather than picking a number of my own.

* The protocol has no authentication layer, and the specification says so in as many words. That is a design decision with a real limit attached: RaftDB is only safe because the App container reaches it on `127.0.0.1:9100` inside the same task, and it can never be exposed beyond that boundary as it stands. A second consumer, in another task or another service, would need either a proxy in front of it or a change to the protocol. I wrote the constraint into the spec instead of leaving it as folklore about how the container happens to be deployed.

* `PLACE_PIXEL`, opcode `0x31`, is the reason RaftDB exists at all. It carries the canvas key, the history key, the pixel index, the four-bit colour and the history entry in one request, so the pixel write and its history record either both happen or neither does. On the Go side that shape is the `PlacementMutation` struct. The capability is deliberately not unconditional: the placement path takes it only when the configured backend satisfies the `AtomicPlacementBackend` assertion, and any other backend falls back to two separate writes with the divergence risk that implies.

* Storage is behind one interface, and its size is honest about the surface involved: `DatabaseBackend` declares 15 methods in four groups, four for config, four for bans, four for milestones and three for history. `AtomicPlacementBackend` is a second, single-method interface rather than a sixteenth method, which is what lets a backend opt out of atomic placement without stubbing something it cannot honour. The repository's own `AGENTS.md` still says sixteen; the interface file is the authority and it says fifteen.

* The week's real obstacle was structural rather than about consensus at all. `store/factory.go` sat in package `store`, and `store/postgres` and `store/filesystem` each import `store` for their interface assertions, so a factory inside `store` that constructed those backends closed an import cycle. The record in `awsplace/learnings.md:1-6` states it directly: those packages import `store`, and the DynamoDB sub-package escaped the problem only because it does not. The fix was to move the factory out into `internal/backends/factory.go`, a package that can import every implementation because nothing imports it back, and that is the package the RaftDB backend gets registered in. Two costs came with it. `store/factory.go` still exists, carrying a deprecation notice that points at the replacement, because deleting it in the same change would have widened the diff past the point I could review it. And `main.go` needed the DynamoDB client treated as optional, with a nil-safe type assertion and the WebSocket, admin and scheduler paths gated on it, which is a conditional the code did not have before.

* The image is four stages, and the boundary between them is what keeps the runtime small: `aws-sdk-builder` compiles aws-sdk-cpp from a pinned commit, `builder` compiles `raftdb_server` against it, `go-tools-builder` produces the Go helper binaries with `CGO_ENABLED=0`, and the runtime stage starts from a clean `ubuntu:24.04` and copies in only what it needs. The SDK is pinned to commit `0c4942f81092d175da061a05a27df8369f70871f` with `BUILD_ONLY=s3`, so an upstream change cannot alter the bytes of an image built from an older application commit. Compiling that SDK from source is the price, and it is the slowest part of the build.

* The container is non-root before it runs anything. Group and user `10001` are created in the image, the data root is chowned to them, and `USER 10001:10001` precedes the entrypoint. That is what makes the EFS access point simple: it is created with `ownerUid` and `ownerGid` of `10001` and permissions `0750`, so the sidecar lands in a directory it already owns and no `chown` is needed at startup over a network filesystem. The volume is mounted with transit encryption and IAM authorization enabled, and the task role's EFS permissions are `ClientMount` and `ClientWrite` conditioned on that specific access point ARN.

* Snapshots go to a bucket that is versioned, encrypted, blocked from public access and restricted to TLS 1.2 or better, with noncurrent versions expiring after 35 days. The task role is granted read and write on the prefix `production/member-1` only. The container publishes on a `RAFTDB_SNAPSHOT_INTERVAL_SECONDS` of `300`, and `RAFTDB_RESTORE_FROM_S3` is `false` in the application stack, because the durable WAL on EFS is the primary recovery source and S3 is the offsite copy. Only one writer owns that WAL, which is a constraint the deployment settings have to respect rather than something the store can arbitrate.

* The retry rules are written down and are deliberately narrow. A `NOT_LEADER` reply, status `0x04`, may be followed by at most one redirect to the advertised leader, with the encoded payload and mutation identity reused exactly rather than regenerated; an ambiguous transport failure may be retried once and shares the same budget, so any request gets at most two sends in total. Only a tagged `XADD` or `PLACE_PIXEL` is eligible, because those two carry a 16-byte mutation ID that the server retains through WAL replay and snapshots. `SET`, `BITFIELD_SET_U4`, `DEL`, `HSET`, `HDEL` and `XDEL` get no automatic retry at all. That pushes the ambiguity back onto the caller for most writes, which is the honest tradeoff: I would rather a caller decide what to do about an uncertain `SET` than have the client silently send it twice.
