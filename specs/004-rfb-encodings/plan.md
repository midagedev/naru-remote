# Implementation Plan: RFB Encodings — Efficient Streaming For Real VNC Servers

**Branch**: `004-rfb-encodings` | **Date**: 2026-05-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/004-rfb-encodings/spec.md`

## Summary

Turn Naru from a Raw-only RFB viewer into a real client: negotiate encodings via `SetEncodings`, decode the efficient ones (CopyRect, Hextile, ZRLE, Tight), handle the streaming-critical pseudo-encodings (LastRect, DesktopSize, Cursor), and adapt quality to the connection. The crux is an architectural shift from "compute each rectangle's byte count, read that slice, decode" (which only works for fixed-size Raw) to **decode-as-you-read** over an incremental `RFBByteReader`, so variable-length/compressed encodings work over a TCP stream that may split a rectangle across reads. All decode logic lives in pure, `swift test`-able `NaruRemoteCore` types proven against crafted fixtures and `FakeRFBServer` transcripts before any "works against a real server" claim.

Current default-changing PRs that touch streaming or interaction behavior must
follow the sustained-usability candidate contract:
`artifacts/benchmarks/2026-06-06-sustained-usability-candidate-contract.md`.

## Constitution Check

- **I. Local-First Composition**: Server→client rendering only. No text path; Compose & Send untouched. The only client→server messages added are transport control (`SetEncodings`/`SetPixelFormat`/fence). ✅
- **II. Tailnet-Native**: No change to connection posture; rides the existing session. ✅
- **III. Verification**: Every decoder is pure + unit-tested with crafted byte fixtures; negotiation + CopyRect/Hextile proven against `FakeRFBServer`; ZRLE/Tight real-server throughput is an explicit residual-risk device pass (no VNC server in env). ✅
- **IV. Security Boundaries**: No pixel/coord/tile/byte-count/latency/JPEG/cursor data logged or exported; only fixed-catalog encoding-name labels. Decoders treat server bytes as untrusted (bounds-checked, allocation-bounded, trap-free) — robustness is a security requirement (SP-006). In-memory zlib context + framebuffer torn down on disconnect. ✅
- **V. Helper Optional**: Pure protocol work; no helper dependency. ✅
- **VI. Phone-First**: iPhone path first in the matrix; cellular bandwidth is the motivating scenario; iPad rides the same decode path. ✅

No constitution violations. One new platform dependency (the `Compression` framework, for ZRLE/Tight only) — justified in research.md; CopyRect/Hextile/negotiation need none.

## Project Structure

### Documentation (this feature)

```
specs/004-rfb-encodings/
├── spec.md       # Feature specification
├── plan.md       # This file
├── research.md   # Technical decisions (reader architecture, zlib, encoding wire formats)
└── tasks.md      # Task breakdown (sequenced increments)
```

### Source Code (repository root)

Almost entirely new pure Core types + a focused refactor of the network read path. No App/UI change except surfacing the DesktopSize resize signal (which reuses `specs/003`'s transform recompute) and the optional encoding-name diagnostic label.

```
NaruRemote/Sources/NaruRemoteCore/VNC/
├── RFBEncoding.swift                 # NEW: encoding/pseudo-encoding code registry + preference builder
├── RFBByteReader.swift               # NEW: incremental byte cursor (Data-backed + connection-backed)
├── RFBFramebufferDecoder.swift       # NEW: multi-encoding dispatch; per-encoding decoders
│                                     #      (Raw/CopyRect/Hextile/ZRLE/Tight) consuming a reader
├── RFBZlibInflateStream.swift        # NEW (Increment 2): session-lifetime persistent zlib inflate
├── RFBClientMessageEncoder.swift     # EDIT: add setEncodings(type 2) + setPixelFormat(type 0) + fence
├── RFBRawFramebufferDecoder.swift    # EDIT: become a thin Raw RFBRectangleDecoder + keep apply() shim
├── RFBNetworkClient.swift            # EDIT: send SetEncodings post-handshake; read via RFBByteReader
└── RFBClientBoundary.swift           # EDIT (if needed): surface negotiated-encoding/resize signal

NaruRemote/Tests/NaruRemoteCoreTests/    # NEW: per-encoding decoder tests, reader tests, preference tests
TestFixtures/FakeRFBServer/Fixtures/      # NEW: copyrect, hextile (+ zrle) hex fixtures
NaruRemote/Tests/FakeRFBServerKitTests/   # NEW: SetEncodings transcript + CopyRect/Hextile integration
```

### Architecture decision: decode-as-you-read

The single most important change. Today:

```
requestFramebufferUpdate → readFramebufferUpdateData (reads ALL bytes, knows w*h*bpp) → RFBRawFramebufferDecoder.apply(Data)
```

After:

```
requestFramebufferUpdate → RFBFramebufferDecoder.decodeUpdate(reader: connectionReader, into: &fb, serverInit:, zlib:)
   per rectangle: read 12-byte header → dispatch by encodingType → RFBRectangleDecoder pulls exactly its bytes from the reader
```

The pure `apply(updateData: Data, ...)` entry point is **kept** (wrapping the `Data` in a `DataByteReader`) so all existing Raw tests and new crafted-fixture tests stay pure and offline. The connection path uses a `ConnectionByteReader` whose `read(n)` calls `connection.readExactly(n)` — so a rectangle that spans TCP reads simply blocks for more bytes. This is the seam that makes every variable-length encoding work without special-casing the network.

## Sequenced Increments (each independently shippable + verified, separate PR)

- **Increment 1 (no external deps, full unit + Fake-RFB coverage)** — `RFBEncoding` + preference builder; `SetEncodings`/`SetPixelFormat` encoders; `RFBByteReader`; multi-encoding `RFBFramebufferDecoder` (Raw preserved); **CopyRect**; **Hextile**; **LastRect** + **DesktopSize**; wire `SetEncodings` into handshake + switch the network read to the reader; Fake-RFB CopyRect/Hextile fixtures + integration. This is the dependency-free bandwidth floor + the negotiation that makes it real. Verify `swift test` + `xcodebuild` iPhone, then PR.
- **Increment 2 (Compression framework)** — `RFBZlibInflateStream` (persistent) + **ZRLE**; zlib-fixture tests incl. cross-rectangle/cross-update persistence; advertise ZRLE in the preference list. Real-server throughput = residual-risk device task. PR.
- **Increment 3 (stretch)** — **Tight** (fill/copy/gradient/JPEG via ImageIO); **Cursor/ExtendedDesktopSize** pseudo-encodings; **adaptive** quality/compression pseudo-encodings driven by `specs/003` `ConnectionQuality`; optional continuous-updates/fence pacing. PR(s).

## Complexity Tracking

The decode-as-you-read refactor touches `RFBNetworkClient`'s read path and `RFBRawFramebufferDecoder`'s API shape — both currently relied on by tests and the frame pump. Mitigation: keep the pure `apply(updateData:)` shim and the `RFBFramebufferUpdateResult` contract byte-for-byte identical so the frame pump, app model, and existing tests are unaffected; the refactor is additive (new reader + dispatcher) with the Raw decoder re-expressed as one `RFBRectangleDecoder` among several. The zlib persistence requirement (Increment 2) is the highest-risk correctness item — covered by an explicit "reset corrupts frame 2" test that proves the requirement.

## Phases

(Phase/task detail lives in tasks.md.)
