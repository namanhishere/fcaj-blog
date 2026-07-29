---
title: "Week 1 Worklog"
date: 2026-06-15
weight: 1
chapter: false
pre: " <b> 1.1. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 1 Objectives:

* Finish onboarding and get an AWS working environment I can deploy from, pinned to one region.
* Understand the r/place problem well enough to commit to a canvas storage format before writing a server.
* Register the Discord application that will later carry authentication, with the smallest scope that works.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Read the internship rules and the report template <br> - Create the AWS account and pick ap-southeast-1 as the single working region <br> - Install and configure the AWS CLI, then confirm the principal with aws sts get-caller-identity | 15/06/2026 | 15/06/2026 | <https://cloudjourney.awsstudygroup.com/> <br> <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html> <br> <https://docs.aws.amazon.com/cli/latest/reference/sts/get-caller-identity.html> |
| 3   | - Read the r/place problem: one shared grid, thousands of writers, every reader must see the same board <br> - **Set the scope:** <br>&emsp; + a Go server owning the canvas buffer and the realtime fan-out <br>&emsp; + Discord as the only identity provider <br>&emsp; + a replicated store chosen later, so the on-the-wire format must not depend on it | 16/06/2026 | 16/06/2026 | <https://www.redditinc.com/blog/how-we-built-rplace> |
| 4   | - Create the Discord application in the Developer Portal <br> - Copy the client id and secret into DISCORD_CLIENT_ID and DISCORD_CLIENT_SECRET <br> - Register a redirect URI that matches DISCORD_REDIRECT_URI exactly, http://localhost:8980/auth/callback for local work <br> - Request the identify scope and nothing else <br> - Put my own Discord user id in ADMIN_DISCORD_IDS | 17/06/2026 | 17/06/2026 | <https://discord.com/developers/docs/topics/oauth2> |
| 5   | - Design the canvas encoding: 4 bits per pixel, 2 pixels per byte, high nibble first <br> - **Fix the index arithmetic:** <br>&emsp; + pixelIndex = y * width + x <br>&emsp; + byteIndex = pixelIndex right-shifted by one <br>&emsp; + an even pixelIndex uses the high nibble, an odd one uses the low nibble <br> - Reserve colour index 15 for empty, so a fresh buffer is 0xFF in every byte | 18/06/2026 | 18/06/2026 | <https://go.dev/ref/spec#Arithmetic_operators> <br> <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Bitwise_AND> |
| 6   | - Write the Go reference implementation in go-ecs/internal/canvas/nibble.go <br> - Port the identical arithmetic to JavaScript for the parity harness in lambda/tests/nibble-parity.js <br> - Cover both directions with nibble_test.go and canvas_test.go <br> - Write down the rule that board dimensions are always read at runtime, never defaulted in code | 19/06/2026 | 19/06/2026 | <https://pkg.go.dev/testing> |

The encoding is small enough to read in one screen, which was the point. `ReadNibble` and `WriteNibble` in `go-ecs/internal/canvas/nibble.go` are the reference every other language copies:

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

### Week 1 Achievements:

* The AWS account is active and every resource I create from here lives in ap-southeast-1. The CLI is configured and `aws sts get-caller-identity` returns the principal I expect, which is the only check I trust before touching a deploy command.

* The canvas encoding is decided and written down: 4 bits per pixel, 2 pixels per byte, high nibble first, `pixelIndex = y * width + x`, `byteIndex = pixelIndex >> 1`, and colour index 15 reserved for empty so that an unpainted board is 0xFF in every byte. `BufferBytesFor(width, height)` rounds `width * height * 4` bits up to whole bytes, and `NewCanvasBuffer` fills the allocation with 0xFF rather than zeroing it.

* I accepted a constraint along with the encoding, and it is the one that will cost me the most later: the packing has to stay **byte-identical across Go, JavaScript, Python and C++**. Go owns the canvas in `go-ecs/internal/canvas/`, the browser client decodes the same buffer it receives on connect, the export tooling reads it from Python, and the storage engine I plan to write will hold it in C++. Four implementations of the same four lines of bit arithmetic is a real maintenance cost. I chose it over one byte per pixel because 8 bits per pixel doubles the size of the full-board payload that every new client downloads, and that payload is the single largest thing the server sends.

* Because the constraint cannot be enforced by a type system across four languages, it has to be enforced by tests. This week that means the Go tests in `go-ecs/internal/canvas/nibble_test.go` and the JavaScript harness `lambda/tests/nibble-parity.js`, which exchange operations through `go_to_js_parity.json` and `js_to_go_parity.json` and compare the resulting buffers. Python and C++ are not in that harness yet; they join when the export tool and the store exist.

* The Discord application exists and requests only the `identify` scope. Nothing about guilds, nothing about messages. A placement needs to be attributable to a stable user id and a cooldown needs to key off it, and `identify` is enough for both.

* One rule came out of reading the problem rather than the code, and it is now written into the conventions: board dimensions are dynamic and are read at runtime from the config store. No constant, no default, no hard-coded 1000. Board expansion in a later week grows the buffer, and any cached dimension would silently corrupt the index arithmetic above.
