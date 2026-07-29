---
title: "Week 2 Worklog"
date: 2026-06-22
weight: 2
chapter: false
pre: " <b> 1.2. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 2 Objectives:

* Build the Go WebSocket server: connection upgrade, a client registry, and broadcast to every connected client.
* Freeze the realtime message names so the frontend and the server can be written against the same protocol.
* Get the whole stack running locally under Docker Compose, with the cross-language canvas check passing.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Choose the WebSocket library: coder/websocket v1.8.14 rather than gorilla/websocket <br> - **Write down the Go conventions this decision sits inside:** <br>&emsp; + no HTTP router framework, plain net/http with Go 1.22+ method routing <br>&emsp; + CGO_ENABLED=0 for static binaries <br>&emsp; + gofmt as the only formatter, packages under internal/ named after their domain | 22/06/2026 | 22/06/2026 | <https://pkg.go.dev/github.com/coder/websocket> <br> <https://pkg.go.dev/net/http#ServeMux> |
| 3   | - Write the hub in go-ecs/internal/ws/hub.go <br> - **Structure:** <br>&emsp; + a clients map guarded by a sync.RWMutex <br>&emsp; + register, unregister and broadcast channels, the broadcast channel buffered at 256 <br>&emsp; + one goroutine in Run owns every mutation of the registry <br> - Write the per-connection read and write loops in client.go | 23/06/2026 | 23/06/2026 | <https://pkg.go.dev/sync#RWMutex> <br> <https://go.dev/doc/effective_go#channels> |
| 4   | - Freeze the realtime protocol in protocol.go: eight message names, seven server to client plus PLACE_PIXEL from the client <br> - Wrap every message in one envelope of type and payload, keeping the payload as json.RawMessage so numeric fields such as colorIndex stay numbers <br> - Define the INIT_DATA payload: full grid, palette, dimensions and cooldown | 24/06/2026 | 24/06/2026 | <https://datatracker.ietf.org/doc/html/rfc6455> <br> <https://pkg.go.dev/encoding/json#RawMessage> |
| 5   | - Implement the origin check in handler.go, before the upgrade and not after <br> - **Rules, in order:** <br>&emsp; + no Origin header, allow, because non-browser clients send none <br>&emsp; + Origin listed in ALLOWED_ORIGINS, allow on an exact or subdomain match <br>&emsp; + ALLOWED_ORIGINS empty, allow only when the origin host equals the request host <br>&emsp; + otherwise deny with 403 <br> - Pass InsecureSkipVerify to websocket.Accept because my own check already ran <br> - Take the client IP from the leftmost X-Forwarded-For entry | 25/06/2026 | 25/06/2026 | <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Origin> <br> <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-For> |
| 6   | - Bring the stack up with docker compose up --build -d <br> - Confirm the port map: server 8980, second server 8981, nginx 19980, raftdb 9100 <br> - Run the cross-language check with node lambda/tests/nibble-parity.js <br> - Paint from two browser tabs and watch PIXEL_UPDATE land on both | 26/06/2026 | 26/06/2026 | <https://docs.docker.com/compose/> |

The order of the two checks in `go-ecs/internal/ws/handler.go` is the part worth quoting, because getting it backwards would hand origin policy to the library:

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

Bringing it up locally is two commands, and the second one is the one I actually watched:

```bash
docker compose up --build -d
node lambda/tests/nibble-parity.js
```

### Week 2 Achievements:

* A working local canvas, end to end. `docker compose up --build -d` starts raftdb on 9100, the Go server on 8980, a second Go server on 8981, and nginx serving the frontend on 19980. The server waits on the raftdb healthcheck, which is a bare TCP probe (`exec 3<>/dev/tcp/127.0.0.1/9100`) rather than a query, so the dependency ordering is real but shallow. A pixel placed in one browser tab appears in the other, delivered as a `PIXEL_UPDATE` broadcast through the hub.

* `node lambda/tests/nibble-parity.js` passes both rounds. Round one reads `go_to_js_parity.json`, replays the operations the Go tests recorded, and checks the resulting buffer hex; round two generates fresh random operations into `js_to_go_parity.json` for the Go side to replay. That is the enforcement mechanism for the byte-identical constraint I took on in week 1, and it is now running rather than aspirational.

* The realtime protocol is fixed at eight names in `go-ecs/internal/ws/protocol.go`: `INIT_DATA`, `PIXEL_UPDATE`, `BOARD_RESIZE`, `ONLINE_COUNT_UPDATE`, `COOLDOWN_START`, `AUTH_REQUIRED` and `ERROR` from the server, plus `PLACE_PIXEL` from the client. Everything travels in one envelope with a `type` string and a `json.RawMessage` payload, which is what keeps `colorIndex` a number instead of a re-encoded string.

* The hub is deliberately boring. A single `Run` goroutine drains the register, unregister and broadcast channels, so the clients map is only ever mutated from one place, and the `sync.RWMutex` exists for readers such as the online count rather than for coordinating writers. The broadcast channel is buffered at 256, which means a burst larger than that blocks the caller instead of dropping updates. I preferred a slow write to a silently missing pixel.

* Named tradeoff on origins: with `ALLOWED_ORIGINS` unset the server falls back to same-origin only. That is the right default for local work, and it also means a deployed frontend served from a different hostname will simply be refused a connection until the variable is set explicitly. `docker-compose.yml` sets it to `http://localhost:19980,http://127.0.0.1:19980` so nginx and the server agree.

* Two things are knowingly unfinished. Placement cooldowns live in memory in the Go process, so restarting the server lets users place again immediately, a caveat already recorded in `awsplace/README.md`. And `AUTH_ENABLED` is `false` in `docker-compose.yml`, so any tab can paint right now. Discord login on Lambda is the next week's work, and until it exists the local canvas is a demo, not a system.
