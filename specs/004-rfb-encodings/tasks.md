# Tasks: RFB Encodings — Efficient Streaming For Real VNC Servers

**Branch**: `004-rfb-encodings` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Tasks are small, independently testable, and declare file ownership. Within an
increment, `[P]` marks tasks with disjoint write sets that *could* run in
parallel; the RFB decoder/reader files are shared and interdependent, so most of
this feature is intentionally **sequential** (one author per file set — a hard
lesson from `specs/003`). Each increment ends green (`swift test` + `xcodebuild`
iPhone) and ships as its own PR.

## Increment 1 — Negotiation + dependency-free encodings (CopyRect, Hextile)

- **T101** `RFBEncoding.swift` (NEW): encoding/pseudo-encoding code registry
  (`Raw=0, CopyRect=1, Hextile=5, Tight=7, ZRLE=16`; `LastRect=-224,
  DesktopSize=-223, ExtendedDesktopSize=-308, Cursor=-239, XCursor=-240,
  DesktopName=-307, Fence=-312, ContinuousUpdates=-313`) + `RFBEncodingPreference`
  pure builder `(supported, pseudo, quality?) -> [Int32]`. Owns: `RFBEncoding.swift`.
- **T102** `RFBEncodingTests.swift` (NEW): preference ordering (most-preferred real
  encoding first, Raw always present + last among reals, pseudo-encodings included).
  Owns: test file.
- **T103** `RFBClientMessageEncoder.swift` (EDIT): add `setEncodings([Int32])`
  (type 2) and `setPixelFormat(RFBPixelFormat)` (type 0). Byte-exact, big-endian.
  Owns: `RFBClientMessageEncoder.swift`.
- **T104** `RFBClientMessageEncoderTests` (EDIT/NEW): byte-exact `setEncodings`
  for a known list; `setPixelFormat` 20-byte layout. Owns: test file.
- **T105** `RFBByteReader.swift` (NEW): `RFBByteReader` protocol (big-endian
  `u8/u16/u32/s32/bytes(n)`) + `DataByteReader` + `RFBByteReaderError`. Owns: file.
- **T106** `RFBByteReaderTests.swift` (NEW): typed reads, big-endian correctness,
  insufficient-data error, cursor advance. Owns: test file.
- **T107** `RFBFramebufferDecoder.swift` (NEW): multi-encoding update loop —
  read 12-byte rect header, dispatch by `encodingType`, apply in wire order,
  produce `RFBFramebufferUpdateResult`; handle **LastRect** (stop) and 0xFFFF count.
  Re-express **Raw** as `RFBRectangleDecoder` here (or call the existing Raw logic).
  Owns: `RFBFramebufferDecoder.swift`.
- **T108** `RFBRawFramebufferDecoder.swift` (EDIT): keep `apply(updateData:serverInit:
  previousFramebuffer:)` + `decode(...)` as the pure shim that wraps `Data` in a
  `DataByteReader` and delegates to `RFBFramebufferDecoder` — **all existing Raw
  tests must pass unchanged**. Owns: `RFBRawFramebufferDecoder.swift`.
- **T109** CopyRect decoder (in `RFBFramebufferDecoder.swift`): snapshot-src→write-dst,
  overlap-safe, bounds-checked; damage = dst. Owns: same file as T107.
- **T110** `RFBCopyRectDecoderTests.swift` (NEW): src→dst copy, overlap, out-of-bounds
  rejection, mixed CopyRect+Raw update. Owns: test file.
- **T111** Hextile decoder (in `RFBFramebufferDecoder.swift`): tile loop, subencoding
  mask, bg/fg carry, raw tiles, coloured + fg subrects. Owns: same file.
- **T112** `RFBHextileDecoderTests.swift` (NEW): each mask bit; bg/fg carry across
  tiles; partial edge tiles; raw tile; coloured vs fg subrects. Owns: test file.
- **T113** DesktopSize pseudo-encoding (in `RFBFramebufferDecoder.swift` +
  `RFBClientBoundary.swift`): reallocate framebuffer, surface `RFBDesktopResize`
  in `RFBFramebufferUpdateResult`. Subsequent rects validate new bounds. Owns: both files.
- **T114** `RFBDesktopSizeTests.swift` (NEW): reallocation, resize signal, post-resize
  rect validation. Owns: test file.
- **T115** `RFBNetworkClient.swift` (EDIT): send `SetEncodings` after handshake (both
  first-frame + session connect paths); add a `ConnectionByteReader` and route
  `requestFramebufferUpdate` through `RFBFramebufferDecoder.decodeUpdate(reader:)`;
  map decode errors to existing `RFBNetworkClientError`. Owns: `RFBNetworkClient.swift`.
- **T116** FakeRFBServer fixtures (NEW): `copyrect-update.hex`, `hextile-update.hex`
  (Raw first frame + encoded second update). Owns: fixture files.
- **T117** `FakeRFBServerEncodingTests.swift` (NEW): assert recorded client transcript
  contains a well-formed `SetEncodings` (CopyRect/Hextile ahead of Raw); decode the
  CopyRect/Hextile second frame end-to-end. Owns: test file.
- **T118** Verify: `swift build && swift test`; `xcodegen generate` (if needed);
  `xcodebuild` iPhone 17 Pro build+test green. Commit; open PR.

## Increment 2 — ZRLE (the cellular bandwidth centerpiece)

- **T201** `RFBZlibInflateStream.swift` (NEW): session-lifetime persistent zlib inflate
  over `Compression` (consume 2-byte RFC-1950 header once, feed raw DEFLATE to a
  persistent stream; `Z_SYNC_FLUSH`-tolerant). Owns: file.
- **T202** `RFBZlibInflateStreamTests.swift` (NEW): round-trip vs zlib-compressed
  fixtures; multi-chunk; persistence across calls. Owns: test file.
- **T203** ZRLE decoder (in `RFBFramebufferDecoder.swift`): CPIXEL sizing, 64×64 tiles,
  raw/solid/packed-palette/plain-RLE/palette-RLE subencodings; pulls from the persistent
  stream. Owns: decoder file.
- **T204** `RFBZrleDecoderTests.swift` (NEW): each tile subencoding; CPIXEL 3-byte path;
  **persistence across rectangles + across updates** (and a "reset corrupts frame 2"
  proof). Owns: test file.
- **T205** Thread the per-session zlib stream through `RFBNetworkClient` (create on
  connect, reset on disconnect/profile change) + add ZRLE to the preference list.
  Owns: `RFBNetworkClient.swift`, `RFBEncoding.swift`.
- **T206** FakeRFBServer ZRLE fixture + integration test. Owns: fixture + test file.
- **T207** Verify green; PR. Residual-risk task: live macOS/TigerVNC ZRLE throughput
  (manual device pass — no server/device in env).

## Increment 3 — Tight, server cursor, adaptive quality (stretch)

- **T301** Tight decoder: fill + JPEG (ImageIO, off main actor) + basic-copy; then
  gradient/palette + multi-stream. Owns: decoder file + zlib stream.
- **T302** Tight tests (crafted + JPEG fixture). Owns: test file.
- **T303** Cursor (-239) / XCursor (-240) decode → `RFBServerCursor` (image + hotspot),
  framebuffer untouched; App wires it as additive to the synthetic cursor. Owns: decoder
  + a small App overlay edit.
- **T304** ExtendedDesktopSize (-308) parsing → resize signal. Owns: decoder file.
- **T305** Adaptive: `RFBEncodingPreference` emits Tight quality-level (−23…−32) /
  compression-level (0…−9) codes from the `ConnectionQuality` bucket (`specs/003`);
  optional continuous-updates/fence pacing + response encoder. The live connection read
  path must preserve buffered bytes across idle timeouts: a zero-byte ContinuousUpdates
  timeout is a non-fatal idle tick, but a timeout/close after consuming part of a server
  message fails the stream. Owns: `RFBEncoding.swift`, `RFBClientMessageEncoder.swift`,
  `RFBNetworkClient.swift`.
- **T306** Tests for adaptive preference + fence response; verify no latency/pixel in
  diagnostic export. Owns: test files.
- **T307** Verify green; PR. Residual-risk: live Tight-JPEG throughput + real resolution
  change (manual device pass).
- **T308** Live benchmark reporting: `VNCLiveBenchmark` emits redacted schema-v5
  latency summaries with avg/p50/p95/min/max for first-frame, full-refresh, and
  continuous-update samples. Owns: tool + benchmark-kit tests. **Done.**
- **T309** Simulator synthetic frame benchmark: opt-in XCTest benchmark for
  framebuffer allocation, steady-state full Metal upload, and small dirty-rect
  upload on an iPhone simulator; skips by default unless explicitly enabled.
  Owns: `SyntheticFramePipelineBenchmarkTests.swift`, benchmark docs. **Done.**
- **T310** Stream pacing backpressure: app default frame stream caps active
  content-frame requests at ~30 fps while keeping fake/test streams able to
  inject `frameInterval: 0`; record VNC performance research and live localhost
  benchmark baseline. Owns: app model default config, app-model test, benchmark
  artifacts. **Done.**
- **T311** Live stream-shape benchmark: extend `VNCLiveBenchmark` schema-v6 with
  a bounded incremental request/response probe that reports delivered FPS,
  empty/content/timeouts, update latency, dirty-rect count, dirty-area permille,
  and changed-pixel permille without emitting target identity, dimensions,
  pixels, byte counts, or raw errors. Owns: live benchmark CLI, benchmark-kit
  summary/tests, benchmark docs. **Done.**
- **T312** In-app stream stats foundation: keep safe aggregate active-session
  counters in `NaruRemoteAppSnapshot` for delivered/content/empty/timeout
  frames, dirty-rect counts, dirty-area permille, changed-pixel permille, and
  coarse thermal state. Do not export host, dimensions, coordinates, pixels,
  byte counts, raw latency, or raw errors. Owns: app snapshot/model/tests.
  **Done.**

## Cross-cutting (every increment)

- No pixel/coord/tile/palette/byte-count/latency/JPEG/cursor data in any log or
  diagnostic export (constitution §IV / SP-005); decode hot path has zero logging.
- Decoders are trap-free and allocation-bounded against hostile server bytes (SP-006).
- iPhone path verified before any iPad path (constitution §VI).
- Protocol claims proven against `FakeRFBServer`/crafted fixtures before "done"; real
  servers are residual-risk device tasks (constitution §III).
