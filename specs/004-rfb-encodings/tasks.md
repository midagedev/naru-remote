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
- **T313** Thermal-aware app pacing: when iOS reports elevated thermal pressure,
  raise the minimum active/idle frame-request delay from the default 30fps path
  to fair/serious/critical tiers, while preserving explicit zero-delay fake/test
  streams. Owns: app pacing policy, app model wiring, app-model tests. **Done.**
- **T314** Profiled stream-shape benchmark: extend `VNCLiveBenchmark` schema-v7
  with `--stream-shape-profiles local-low-latency|all` so sustained incremental
  FPS/latency/dirty-area aggregates can be compared across Hextile, Tight, ZRLE,
  and adaptive profiles before changing app defaults. Owns: live benchmark CLI,
  benchmark-kit profile report/tests, benchmark docs. **Done.**
- **T315** Gate adaptive re-encoding: keep connection-quality UI sampling but
  leave automatic Tight/ZRLE/ContinuousUpdates renegotiation off by default
  until longer live iPhone benchmarks prove it improves sustained interaction.
  Owns: app-model guard/tests. **Done.**
- **T316** Benchmark failure taxonomy: move live-benchmark safe failure labeling
  into the benchmark kit, cover network timeout / byte-reader / zlib / auth
  labels with tests, and record an 8-sample all-profile stream-shape comparison
  before changing default encodings. Owns: benchmark kit, CLI, tests, benchmark
  artifact. **Done.**
- **T317** Long-run benchmark profile selection: let `VNCLiveBenchmark` skip
  or narrow the first-frame/full-refresh profile sweep independently from
  stream-shape probes, so practical iPhone/Mac sustained-stream experiments
  can run longer without repeatedly paying an all-profile startup sweep. Owns:
  live benchmark CLI, benchmark-kit selection tests, benchmark docs. **Done.**
- **T318** Cursor-only empty update handling: when an incremental update carries
  a server cursor pseudo-encoding but no changed pixels, publish the memory-only
  cursor shape while keeping the unchanged framebuffer out of the GPU/PiP
  republish path. Owns: app model/tests. **Done.**
- **T319** Same-frame Metal upload gate: keep SwiftUI-only redraws such as
  cursor overlay changes from re-enqueueing the identical framebuffer into the
  Metal upload path, while preserving uploads when dirty rectangles or pixel
  storage change. Owns: session viewer upload gate/tests. **Done.**
- **T320** Same-frame Metal redraw gate: only request an `MTKView` redraw after
  a framebuffer was actually enqueued, so cursor/control-only SwiftUI redraws
  do not also redraw the unchanged texture, and add an opt-in simulator
  benchmark for the upload-gate skip path. Owns: Metal view coordinator,
  benchmark target. **Done.**
- **T321** Live benchmark app pacing parity: let stream-shape probes use a
  separate empty-update idle delay so sustained live measurements can mirror
  the app's content-frame and static-screen backpressure separately. Owns:
  live benchmark CLI/report/docs. **Done.**
- **T322** Adaptive idle stream backoff: increase the app's empty-update delay
  only after sustained static-screen replies, reset immediately on content
  frames, and keep thermal pacing / zero-delay test streams deterministic.
  Owns: session stream pacing policy, app stream loop, tests. **Done.**
- **T323** Live benchmark adaptive idle parity: mirror the app's sustained
  empty-update backoff inside stream-shape probes, expose `app|none` mode, and
  report schema-v10 pacing settings for comparable iPhone/Mac runs. Owns:
  benchmark kit, live benchmark CLI/report/docs, tests. **Done.**
- **T324** Renderer upload strategy diagnostics: share the renderer's safe
  full-vs-partial upload classifier between app diagnostics and live benchmark
  summaries, exposing only aggregate counts/permille and upload-region maxima
  so hot-device reports can identify full-upload pressure without dimensions,
  coordinates, pixels, or byte counts. Owns: core classifier, app stats/export,
  live benchmark summary/docs/tests. **Done.**
- **T325** Stream transport benchmark comparison: extend `VNCLiveBenchmark`
  schema-v12 with `--stream-shape-transport request-response|continuous-updates|both`
  and a redacted transport-mode field on every stream-shape report, applying a
  ContinuousUpdates/Fence pseudo-encoding overlay only for the continuous mode so
  sustained FPS/latency/renderer-upload aggregates can compare request/response
  polling against push transport before changing app defaults. Owns: live
  benchmark CLI, benchmark-kit report/tests, research notes, simulator benchmark
  artifact. **Done.**
- **T326** Phase-aware live benchmark failure labels: prefix safe benchmark
  failure labels with fixed catalog phases for stream connect, first frame,
  incremental request/response, ContinuousUpdates stream receive, and standalone
  ContinuousUpdates probe connect/first-frame/enable/receive. Record the
  local-redacted transport comparison showing request/response works while
  ContinuousUpdates fails after receive. Owns: benchmark failure label kit,
  CLI, tests, live benchmark artifact. **Done.**
- **T327** Targeted stream-shape profile lists: allow `VNCLiveBenchmark`
  `--stream-shape-profiles` to accept comma-separated safe profile labels after
  an all-profile sweep, preserving redacted schema output while avoiding long
  runs over known-losing profiles. Record the 45-sample all-profile
  request/response comparison and the 60-sample candidate-list follow-up run.
  Owns: benchmark profile selection kit/tests, live benchmark CLI/docs,
  benchmark artifact. **Done.**
- **T328** Benchmark-backed default encoding profile: switch the production
  `localLowLatency` negotiation from Hextile-first to Tight-first with
  Hextile/Raw fallback, keeping ZRLE and ContinuousUpdates off by default based
  on the redacted 45/60-sample live comparisons, then record a post-change
  24-sample live smoke. Owns: core encoding preference, negotiation tests,
  app-model comment, benchmark artifact. **Done.**
- **T329** Stream-shape tail bucket diagnostics: extend benchmark schema with
  fixed-threshold slow-frame counts (250 ms / 1000 ms) and aggregate
  content/full-dirty/full-upload correlation, so sustained-session tail spikes
  can be triaged without emitting target identity, dimensions, coordinates,
  pixels, byte counts, or raw errors. Owns: benchmark summary kit, CLI output,
  tests, benchmark docs/artifact. **Done.**
- **T330** Content-frame FPS reporting: split stream-shape delivered FPS into
  all-update FPS and content-update FPS so sustained-session reports reflect
  actual visible frame cadence separately from empty update polling. Owns:
  benchmark summary kit, CLI output, tests, benchmark docs/artifact. **Done.**
- **T331** Benchmark-backed fast content pacing: compare 33 ms, 16.7 ms, and
  0 ms request/response content-frame intervals with redacted live stream-shape
  probes, then raise the production active request cap from 30 Hz to 60 Hz
  while preserving separate idle empty-update backoff and thermal floors.
  Owns: app model default, app-model test, benchmark docs/artifact, research
  notes. **Done.**
- **T332** Low Power Mode stream pacing: sample the platform low-power state
  in the app frame loop and raise the minimum active/idle request delay while
  Low Power Mode is enabled, without exporting that state or breaking explicit
  zero-delay fake/test streams. Owns: app pacing policy, app model wiring,
  app-model tests, research notes. **Done.**
- **T333** Low-power stream-shape benchmark parity: extend `VNCLiveBenchmark`
  schema v16 with `--stream-shape-power-mode normal|low-power`, mirror the
  app's Low Power Mode content/idle floors inside stream-shape probes, and
  record a redacted normal-vs-low-power live comparison for sustained-session
  tuning. Owns: benchmark kit policy, CLI/report/docs/tests, benchmark
  artifact. **Done.**
- **T334** Duration-capped sustained stream-shape benchmark: extend
  `VNCLiveBenchmark` schema v17 with `--stream-shape-duration-seconds` so
  thermal/FPS investigations can run for a fixed wall-clock duration, including
  duration-only runs via `--stream-shape-samples 0`, and cap in-flight update
  waits/pacing sleeps to the remaining duration. Owns: CLI/report/docs, live
  smoke artifact. **Done.**
- **T335** Sustained duration candidate evidence: run schema v17 duration-only
  live comparisons for normal/low-power pacing, request/response vs
  ContinuousUpdates transport, and selected encoding/adaptive profiles; record a
  redacted artifact and keep production ContinuousUpdates/adaptive defaults
  conservative until longer physical-device evidence exists. Owns: benchmark
  artifact, research notes. **Done.**
- **T336** App stream power-saver control: add a persisted non-secret
  `balanced|power-saver` viewer setting, expose it as a compact session control,
  and feed it into the same app pacing floor used by iOS Low Power Mode while
  keeping `balanced` as the default `{}` settings-file shape. Owns: app settings,
  app model, session viewer, tests, research notes. **Done.**
- **T337** Benchmark profile recommendation: extend `VNCLiveBenchmark` schema
  v18 with a safe request/response profile recommendation derived from
  stream-shape profile probes, ranking by aggregate update latency, p95 latency,
  renderer full-upload ratio, slow samples, and content FPS. Record a redacted
  localhost profile comparison showing `zrle-compression-0` as a stronger normal
  sustained candidate while low-power results remain close. Owns: benchmark kit,
  CLI/report output, tests, benchmark artifact, research notes. **Done.**
- **T338** Default server cursor request: after 60 second normal/low-power
  redacted live comparisons showed mixed Tight-first vs ZRLE-compression-0
  winners, keep the production real-encoding order conservative but add
  Cursor/XCursor pseudo-encodings to `localLowLatency` so trackpad mode can use
  real server cursor shapes when the server supports them. Owns: encoding
  preference, tests, benchmark artifact, research notes. **Done.**
- **T339** Receive-path timing benchmark split: attach optional safe timing to
  live `RFBFramebufferUpdateResult` values, propagate it through the frame pump,
  and extend `VNCLiveBenchmark` schema v19 with aggregate receive-total,
  network-read, and client-processing millisecond summaries. This distinguishes
  socket wait from local decode/dispatch pressure when investigating hot iPhone
  sustained sessions, without emitting host identity, dimensions, coordinates,
  pixels, byte counts, raw timing samples, or raw errors. Owns: core result,
  network client, frame pump, benchmark kit/CLI/tests, benchmark docs/artifact.
  **Done.**
- **T340** Timed receive-profile comparison: run schema v19 20 second
  duration-only localhost comparisons for `local-low-latency` vs
  `zrle-compression-0` under normal and low-power pacing, recording only
  redacted aggregate update/receive/network/client-processing timing. Keep the
  static production encoding default unchanged until longer physical-iPhone
  evidence is stable across power modes. Owns: benchmark artifact, research
  notes. **Done.**
- **T341** App receive-timing diagnostic buckets: propagate optional
  framebuffer receive timing into active-session diagnostics as coarse
  `notMeasured|subFrame|interactive|lagging|stalled` buckets for total receive,
  network read, and client processing averages/maxima. Bump diagnostics schema
  to v6 while continuing to exclude raw milliseconds, raw timing samples, host
  identity, dimensions, coordinates, pixels, byte counts, device power state,
  and raw errors. Owns: app snapshot, diagnostic export, tests, diagnostics
  spec notes. **Done.**
- **T342** Actual encoding mix benchmark telemetry: count the actual safe
  framebuffer encoding labels observed in decoded updates, propagate them
  through the frame pump, and extend `VNCLiveBenchmark` schema v20 with sample
  and aggregate stream-shape encoding mixes. This distinguishes requested
  encoding profiles from what the server actually sent without emitting target
  identity, dimensions, coordinates, pixels, byte counts, compressed payloads,
  raw errors, or unsupported raw encoding codes. Owns: core result/decoder,
  frame pump, benchmark kit/CLI/tests, benchmark docs/research notes.
  **Done.**
- **T343** Adaptive client-pressure stream pacing: detect repeated content
  frames whose local client-processing timing is lagging, then temporarily apply
  the existing power-saver pacing floor for the active stream without changing
  the persisted viewer setting or exporting raw timing samples. Ignore
  network/server wait, empty updates, and idle timeouts as triggers. Owns: app
  pacing state, app model wiring, tests, research notes. **Done.**
- **T344** App-model adaptive pacing branch integration test: inject a test-only
  pacing sleeper into the app frame loop and prove that repeated lagging content
  frames switch the actual `NaruRemoteAppModel` stream path from the configured
  active cadence to the adaptive power-saver floor without persisting power
  saver mode. Owns: app model seam, app-model test. **Done.**
- **T345** Benchmark adaptive client-pressure pacing parity: extend
  `VNCLiveBenchmark` schema v21 with `--stream-shape-client-pressure off|app`
  so sustained live comparisons can mirror the app's repeated lagging
  client-processing content-frame trigger and compare normal versus temporary
  adaptive power-saver pacing without exporting raw timing samples. Owns:
  benchmark pacing policy/state, CLI/report output, tests, benchmark docs.
  **Done.**
- **T346** App adaptive pressure empty-update parity: keep empty incremental
  updates from breaking the app's lagging content-frame streak so the live app
  and `VNCLiveBenchmark --stream-shape-client-pressure app` interpret sparse
  content streams consistently, while still resetting on transport idle
  timeout. Owns: app pacing state and app-model tests. **Done.**
- **T347** Benchmark adaptive pressure activation aggregates: extend
  `VNCLiveBenchmark` schema v22 stream-shape summaries with aggregate adaptive
  client-pressure pacing sample count/permille so sustained heat/FPS runs can
  tell whether `--stream-shape-client-pressure app` actually affected pacing
  without exporting raw timing samples. Owns: benchmark summary/report/tests
  and benchmark docs. **Done.**
- **T348** App adaptive pressure activation diagnostics: export safe active-session
  aggregate adaptive client-pressure pacing sample count/permille in diagnostics
  schema v8 so real-device heat/FPS reports show whether app-side pressure
  pacing activated, without exporting raw timing samples, power state,
  dimensions, coordinates, pixels, byte counts, or raw errors. Owns: app
  snapshot, app model wiring, diagnostic export, tests. **Done.**
- **T349** Power-saver sustained encoding profile: keep balanced sessions on the
  static Tight-first `localLowLatency` default, but have explicit viewer
  power-saver or system Low Power Mode sessions re-advertise a request/response
  ZRLE compression-0 profile with server cursor pseudo-encodings before the
  frame loop, using fixed catalog codes only. Owns: encoding preference, app
  model wiring, tests, research notes. **Done.**
- **T350** Benchmark-backed balanced ZRLE default: after schema v20+ actual
  encoding-mix duration runs showed the current balanced Tight-first default was
  served as Raw while ZRLE compression-0 negotiated actual ZRLE with much lower
  client-processing tails, switch `localLowLatency` to the same ZRLE
  compression-0/server-cursor request used for sustained sessions. Keep
  ContinuousUpdates/adaptive renegotiation off by default. Owns: encoding
  preference, tests, benchmark artifact, research notes. **Done.**
- **T351** App frame-apply pressure diagnostics: measure safe aggregate
  MainActor frame-apply timing buckets after each delivered frame, export them
  in diagnostic schema v11, and let repeated lagging app-apply content frames
  trigger the same temporary adaptive power-saver pacing floor as lagging
  client-processing frames. Owns: app model, session stats, diagnostics export,
  tests, research notes. **Done.**
- **T352** Actual renderer upload timing diagnostics: measure successful Metal
  texture-upload elapsed time in the renderer, aggregate sample count plus
  average/max timing buckets in active-session diagnostics schema v12, and keep
  raw milliseconds memory-only so hot-device reports can distinguish app-apply
  pressure from renderer-upload pressure without exporting dimensions,
  coordinates, pixels, byte counts, power state, or raw timing samples. Owns:
  Metal renderer/view wiring, app stats/export, tests, research notes.
  **Done.**
- **T353** Viewport redraw pressure diagnostics: batch local Metal viewport
  gesture/redraw counters inside the UIKit host, flush them to the app model at
  gesture boundaries, and export only safe aggregate counts plus refresh-rate
  bucket in active-session diagnostics schema v13. This lets physical iPhone
  reports distinguish stream/frame upload pressure from local viewport redraw
  pressure without exporting coordinates, pixels, device model, raw timestamps,
  or user content. Owns: Metal view wiring, app stats/export, tests, benchmark
  artifact. **Done.**
- **T354** Moderate adaptive pressure pacing: keep the severe 80 ms / 3 content
  frame adaptive trigger, but also activate the same temporary power-saver
  pacing floor after sustained moderate local work at 34 ms / 8 content frames.
  Mirror the trigger in `VNCLiveBenchmark --stream-shape-client-pressure app`
  so heat/FPS runs can reproduce runtime behavior without exporting raw timing
  samples. Owns: app pacing state, benchmark pacing state, tests, research note,
  benchmark artifact. **Done.**
- **T355** Benchmark-backed balanced 30fps cadence: switch the production
  balanced active request cadence from 60fps-class to the shared 30fps-class
  sustained-session floor, make `VNCLiveBenchmark` use the same default
  stream-shape frame interval, and extend benchmark schema/output so both
  severe and sustained adaptive pressure thresholds are visible. Owns: shared
  pacing defaults, app default configuration, benchmark CLI/report/tests,
  research note, benchmark artifact. **Done.**
- **T356** Smooth viewport hot path and compose draft sync: keep pinch, zoomed
  pan, deceleration, and trackpad auto-pan visible on the Metal/UIKit hot path
  while deferring SwiftUI viewport-state publication until gesture end; also
  propagate local Compose draft text during marked-text composition without
  overwriting UIKit's in-flight multilingual input. Owns: Metal viewport host,
  RemoteInputDock sync policy, tests. **Done.**
- **T357** Display-linked viewport transform coalescing: coalesce pinch,
  zoomed-pan, and trackpad auto-pan layer-transform applications onto one
  display-link tick while preserving immediate parent sync/layout updates and
  flushing the final transform at gesture end. Owns: Metal viewport host,
  coalescer state, tests, research note. **Done; superseded by T358 after
  device feedback showed visible transform deferral felt sticky.**
- **T358** Restore immediate visible viewport transforms and harden Compose
  marked-text commit: keep pinch, zoomed-pan, and trackpad auto-pan layer
  transforms synchronous on the UIKit/Core Animation hot path while preserving
  gesture-end SwiftUI/PiP state publication; reconstruct pre-commit Compose text
  from view text, marked text, controller text, and fallback before `unmarkText`
  so a short UIKit commit snapshot cannot drop the final Korean/CJK candidate.
  Owns: Metal viewport host, RemoteInputDock commit policy, tests, research
  note. **Done.**
- **T359** Stream pacing diagnostics: export safe aggregate pacing-delay buckets
  plus thermal, power-saver, and empty-backoff pacing sample counts in
  diagnostics schema v15, and classify pacing decisions in the app stream loop
  without exporting raw delay samples, device power state, host identity,
  dimensions, coordinates, pixels, byte counts, or draft text. Owns: app pacing
  policy/state, diagnostic export, app/model tests, research note. **Done.**
- **T360** Viewport-interaction stream pacing and Compose stale-binding guard:
  while pinch, zoomed pan, or zoomed trackpad auto-pan is active, apply a
  temporary stream pacing floor so incoming frame request/decode work does not
  compete with local gesture rendering; export only the safe aggregate
  viewport-interaction pacing sample count in diagnostics schema v16. Also
  prevent stale SwiftUI binding writes from overwriting UIKit text immediately
  after Korean/CJK marked-text commit. Owns: app pacing policy/loop, diagnostic
  export, RemoteInputDock sync policy, app/model tests. **Done.**
- **T361** Viewport-interaction live benchmark parity: extend
  `VNCLiveBenchmark` schema v25 with
  `--stream-shape-viewport-interaction off|app`, mirror the app's temporary
  viewport-interaction content/idle pacing floors inside stream-shape probes,
  and report only aggregate viewport-interaction pacing sample count/permille
  plus fixed floor constants. Owns: benchmark pacing policy, CLI/report,
  summary tests, research note. **Done.**
- **T362** Zoomed trackpad cursor travel and Compose local binding continuity:
  reduce zoomed trackpad pan coupling so most touch travel remains visible as
  cursor travel while viewport pan still follows the pointer, and update the
  Compose UIKit bridge so marked-text candidate changes refresh local SwiftUI
  binding state without propagating draft text to the model until composition
  commits. Owns: pointer resolver, Remote Input Dock UIKit bridge, tests,
  research note. **Done.**
- **T363** Viewport stutter diagnostic ratios: make active-session diagnostics
  export safe aggregate permille ratios for gesture long-frame density and
  incoming-frame redraw deferral during viewport interaction, and wire the
  existing redraw request/flush counters to the UIKit viewport hot path. Owns:
  Metal viewport host, app stream stats, diagnostic export, tests, research
  note. **Done.**
- **T364** Viewport stutter diagnostic hints: derive a fixed-catalog
  `viewportStutterHint` from safe viewport long-frame and incoming-redraw
  deferral ratios so physical iPhone diagnostic reports can distinguish local
  gesture-loop pressure from intentional stream redraw deferral without raw
  timestamps, coordinates, pixels, dimensions, byte counts, or device identity.
  Owns: diagnostic export, app snapshot tests, research note. **Done.**
- **T365** Smoother physical viewport and Compose send fallback: let a bounded
  trickle of incoming frames redraw during viewport gestures, treat trackpad
  drags as a hot viewport interaction even before auto-pan is needed, tighten
  trackpad pointer/cursor coalescing, and extend Compose send stabilization for
  slower Korean/CJK marked-text commits. Owns: Metal viewport host, app model
  pointer cadence, Remote Input Dock send policy, tests, research note.
  **Done.**
- **T366** Physical viewport state and Mac paste stability: keep visible Metal
  viewport transforms immediate, but publish the coalesced viewport transform to
  SwiftUI/PiP state on a display-link cadence instead of gesture end only; align
  `.commandV` paste with documented Mac VNC `Alt_L+v` mapping and increase the
  remote clipboard settle window to 300 ms with regression tests proving paste
  is not sent during the old 180 ms optimistic window. Owns: Metal viewport
  host, RFB paste encoder, app model Compose send, tests, research note.
  **Done.**
- **T367** Physical viewport recovery and unconfirmed UTF-8 Compose guard:
  move SwiftUI/PiP viewport-state mirroring for hot Metal gestures back to
  gesture-end flushes so display-link state publication cannot compete with
  touch tracking, and reject Korean/CJK/emoji Compose payloads before clipboard
  writes when the server has not confirmed Extended Clipboard UTF-8 support.
  Owns: Metal viewport host, text-injection policy, app model, tests, research
  note. **Done.**
- **T368** Mid-gesture remote redraw cadence: raise the bounded incoming-frame
  redraw trickle during active viewport gestures from 15 Hz to 30 Hz so zoom
  and pan keep visible remote changes moving while still rejecting 60 Hz
  upload/redraw floods that can heat phones. Owns: Metal viewport host,
  viewport redraw throttle test, research note. **Done.**
- **T369** Physical gesture/Compose correction: after real iPhone feedback
  still reported choppy zoom/pan and unreliable Compose, make active viewport
  gestures strict-defer all pending framebuffer uploads until gesture end,
  pause immersive control auto-hide while the viewport is manipulated, and
  change UTF-8 Compose routing so helper remains preferred, explicit VNC
  unsupported still fails, and unconfirmed VNC support attempts a best-effort
  legacy paste with `unknown` status. Owns: Metal viewport host, session
  viewport chrome, text-injection policy, app model, tests, research note.
  **Done.**
- **T370** Viewport-interaction stream cooldown: after redacted local
  Screen Sharing stream-shape benchmarks showed request/response ZRLE with
  partial uploads but ContinuousUpdates failure and occasional full-dirty
  tails, lower the active viewport-interaction stream pacing floor to an
  8 Hz-class content cadence with 200 ms idle polling. Share the constants
  between the app and `VNCLiveBenchmark`, and update app/benchmark tests plus
  research evidence. Owns: Core pacing defaults, app pacing policy, benchmark
  pacing parity, tests, research note. **Done.**
- **T371** Touch-first viewport request pause and live Compose draft sync:
  after physical iPhone feedback still reported stepped zoom/pan and unreliable
  Compose input, pause new RFB framebuffer update requests while a local
  viewport gesture is active and an existing frame is visible, keeping only
  already-in-flight frame deferral for the gesture-end flush. Also propagate
  marked-text Compose changes to the app model draft while still deferring
  UIKit binding writes so IME composition is not overwritten. Owns: app frame
  stream loop, Remote Input Dock sync policy, tests, research note. **Done.**
- **T372** Viewport request-pause benchmark parity: bump `VNCLiveBenchmark`
  schema v26 so `--stream-shape-viewport-interaction app` mirrors the
  touch-first app behavior by inserting visible-frame request-pause windows
  before incremental samples instead of applying post-frame pacing floors.
  Report only configured pause window, fixed poll interval, aggregate paused
  request count/permille, poll count, and paused milliseconds. Owns: benchmark
  kit, live benchmark CLI/report/tests, benchmark artifact, research note.
  **Done.**
- **T373** App viewport request-pause diagnostics: bump diagnostic export
  schema v21 with safe aggregate viewport request-pause count, poll count,
  average pause timing bucket, and max pause timing bucket so physical iPhone
  logs can show whether touch-first request suppression activated without
  exporting raw timestamps, host identity, dimensions, coordinates, pixels,
  byte counts, or draft text. Owns: app stream stats, app model pause loop,
  diagnostic export/tests, research note. **Done.**
- **T374** Physical gesture and IME hot-path pressure cut: keep local
  trackpad cursor and zoomed auto-pan immediate in the Metal host while
  coalescing remote trackpad pointer writes and SwiftUI cursor mirror publishes
  at lower cadence; defer UIKit marked-text adoption/model propagation until
  IME composition commits so Korean/CJK Compose does not round-trip through the
  app model mid-composition. Owns: app model pointer cadence, Remote Input Dock
  sync policy/tests, research note. **Done.**
- **T375** Request-pause diagnostic interpretation hint: bump diagnostic export
  schema v22 with a fixed-catalog `viewportRequestPauseHint` derived from
  viewport interactions, request-pause activity, gesture long-frame pressure,
  and incoming-frame deferral pressure so physical iPhone reports can show
  whether request suppression was missing, active-but-local-pressure-bound, or
  active-with-incoming-frame deferral. Owns: diagnostic export/tests, research
  note. **Done.**
- **T376** Physical iPhone viewport/Compose regression correction: after device
  feedback still reported stepped zoom/pan and broken Compose input, restore
  the shared active viewport-interaction content cadence to 8 Hz-class so
  decode/upload work cannot compete with local Metal pinch/pan tracking, and
  allow UTF-8 Compose payloads on unconfirmed VNC clipboard servers to take the
  best-effort legacy paste path while explicit unsupported servers still fail
  with helper-aware diagnostics. Owns: Core pacing defaults, text-injection
  policy, app model tests, adapter tests, research note, benchmark artifact.
  **Done.**
- **T377** Physical iPhone smoothness and honest Compose follow-up: after real
  device feedback still reported unnatural zoom/pan and non-working Compose,
  lower zoomed trackpad follow-pan coupling, move viewport-interaction content
  pacing to a conservative 4 Hz-class floor, and supersede T376's unconfirmed
  UTF-8 best-effort path so Korean/CJK/emoji Compose without confirmed UTF-8
  clipboard or reachable helper fails before writing clipboard bytes. Owns:
  Core pacing defaults, pointer resolver, text-injection policy, focused app /
  core tests, research note, benchmark artifact. **Done.**
- **T378** Trace-backed trackpad edge auto-pan smoothness: add a synthetic
  high-refresh gesture trace proving near-edge zoomed trackpad auto-pan cannot
  move the visible cursor opposite the finger, then cap reveal-only follow pan
  to the current touch sample. Owns: pointer resolver/tests, session task note,
  research note, smoothness benchmark artifact. **Done.**
- **T379** Compose route diagnostic v23: add pre-send diagnostic fields for
  Compose payload encoding, planned injection path, active UTF-8 clipboard
  support, and fixed route blocker so physical iPhone logs can distinguish
  helper-not-configured from helper-ready and confirmed UTF-8 paths without raw
  draft text. Owns: diagnostic export schema/tests, app-model route
  classification tests, helper spec task note, diagnostic artifact. **Done.**
- **T380** Practical iPhone VNC baseline v1: stop treating each zoom/pan and
  Compose complaint as an isolated tweak and establish a larger pass/warn/fail
  target for sustained iPhone sessions. Add a safe `VNCLiveBenchmark` practical
  assessment covering content FPS, p95 update latency, client processing tail,
  renderer full-upload pressure, and adaptive pacing pressure; publish it in
  schema v27 JSON and human output. Fold in the matching app-side fixes by
  keeping Metal viewport transforms immediate while mirroring viewport state at
  a bounded 30 Hz cadence, and by allowing unconfirmed UTF-8 VNC clipboard
  Compose to take the explicit best-effort legacy paste path while known
  unsupported UTF-8 still fails with helper-aware diagnostics. Owns: benchmark
  kit/CLI/tests, Metal viewport host, text-injection policy, app model/snapshot
  tests, benchmark artifact. **Done.**
- **T381** ZRLE changed-bounds upload pressure cut: after the practical baseline
  showed full-screen ZRLE wire rectangles with sparse actual pixel changes,
  report tile-bounded actual ZRLE changed rectangles instead of treating every
  ZRLE wire rectangle as renderer damage. Thread safe changed-pixel counts into
  the Metal upload plan, let sparse large-damage frames stay on partial uploads,
  and enter adaptive client-pressure pacing after one 1000 ms-class local
  decode/apply spike. Bump `VNCLiveBenchmark` to schema v28 with the fixed
  single-spike threshold, benchmark localhost Screen Sharing again, and record
  that renderer full-upload pressure reaches 0 permille while the practical
  baseline still fails on decode/update tail. Owns: RFB decoder damage
  reporting, upload plan/renderer/view plumbing, app and benchmark pacing,
  focused tests, benchmark artifact. **Done.**
- **T382** Cold-spike pressure cooldown and pseudo-encoding isolation: after
  post-upload-cut benchmarks showed the first stream profile could receive one
  2 second-class local-work spike regardless of Cursor/ExtendedClipboard
  requests, add benchmark-only ZRLE compression-0 cursor/clipboard isolation
  profiles, keep the app's default `local-low-latency` profile, and split app
  plus benchmark adaptive recovery so a single very-slow spike cools for a
  short fixed update window while repeated lag/full-upload pressure keeps the
  long sustained recovery. Bump `VNCLiveBenchmark` to schema v29 with the
  very-slow recovery count, update docs/research, and record safe localhost
  Screen Sharing benchmark evidence. Owns: Core pacing defaults, app pressure
  state, benchmark pacing/report/profile list, focused tests, benchmark
  artifact, research note. **Done.**
- **T383** Tail-position benchmark telemetry: after the cold-spike cooldown
  split, expose safe ordinal aggregates for the first slow and very-slow
  update/content update inside `tailLatency`, bump `VNCLiveBenchmark` to schema
  v30, and print the first very-slow ordinal in human output so future PRs can
  distinguish cold first-content-frame tails from later recurring decode/apply
  stalls without exporting raw per-frame samples. Owns: benchmark summary kit,
  CLI report output, focused tests, benchmark docs, research note. **Done.**
- **T384** ZRLE decode phase baseline: establish a larger practical baseline
  unit for sustained iPhone-class VNC streaming by splitting safe aggregate
  ZRLE decode timings into inflate and tile/apply phases, threading them from
  the framebuffer decoder through `RFBFramePumpFrame`, and publishing
  `VNCLiveBenchmark` schema v31 summaries. Use the first v31 localhost Screen
  Sharing run to decide whether the next optimization axis is local decode,
  renderer upload, request pacing, or server/network wait. Owns: decoder
  metrics, frame pump metadata, benchmark kit/CLI/tests, benchmark artifact,
  research note. **Done.**
- **T385** Core practical stream matrix: add a named `VNCLiveBenchmark`
  `--stream-shape-profiles core-matrix` selection that expands to the current
  default, pure ZRLE compression-0, Tight-first, and adaptive-good-full
  candidates, so larger optimization PRs can compare request/response versus
  ContinuousUpdates without running every historical profile. Record a redacted
  v31 localhost Screen Sharing matrix, keep `local-low-latency` as default, and
  identify controlled dynamic-content stimulus as the next large benchmark
  unit. Owns: benchmark profile selection kit/tests, CLI docs, benchmark
  artifact, research note. **Done.**
- **T386** Dynamic-content live stimulus: extend `VNCLiveBenchmark` schema v32
  with `--stream-shape-stimulus off|external-command`, add a repo-native
  `VNCLiveStimulusWindow` macOS helper for local Screen Sharing runs, launch the
  stimulus before each stream-shape first full frame, use a minimal child launch
  environment without forwarding VNC target variables, and record a redacted
  stimulated `core-matrix` request/response baseline. Use the result to pick
  profile/extension isolation as the next large unit rather than changing the
  production default immediately. Owns: benchmark kit/CLI, SwiftPM helper
  target, tests, benchmark docs/artifact, research note. **Done.**
- **T387** ZRLE stimulated isolation matrix: add
  `--stream-shape-profiles zrle-isolation` for the current default, pure ZRLE
  compression 0, and cursor/ExtendedClipboard extension combinations. Record a
  redacted stimulated request/response run and use the evidence to identify
  order/cold-start neutral scoring as the next larger unit before changing the
  production default. Owns: benchmark profile selection kit/tests, CLI docs,
  benchmark artifact, research note. **Done.**
- **T388** Order-neutral live profile scoring: extend `VNCLiveBenchmark` schema
  v33 with repeated stream-shape profile probes, fixed/rotated profile ordering,
  per-probe iteration/order ordinals, per-profile aggregate reports, and an
  order-neutral recommendation. Record a redacted stimulated `zrle-isolation`
  run with every profile leading one iteration, keep the production default
  unchanged, and use the evidence to target explicit warm-up/preflight behavior
  next. Owns: benchmark kit/CLI/tests, benchmark docs/artifact, research note.
  **Done.**
- **T389** Benchmark warm-up/preflight gate: extend `VNCLiveBenchmark` schema
  v34 with `--stream-shape-preflight-frames N`, consuming a bounded number of
  hidden incremental frames after the stream-shape first frame and before
  measured samples. Record a redacted stimulated `zrle-isolation` run with one
  hidden preflight frame, keep the production app default unchanged, and use the
  evidence to decide whether app-side hidden preflight deserves a physical
  iPhone pass. Owns: benchmark CLI/report/docs, benchmark artifact, research
  note. **Done.**
- **T390** App-side preflight production gate: after v34/v35 showed hidden
  preflight can remove the `local-low-latency` very-slow cold tail but still
  leaves content FPS below the sustained usability target, test whether enabling one
  hidden post-first-frame incremental preflight in the app improves physical
  iPhone hand feel without making the just-connected screen feel stale. Verify
  with a 10 minute physical iPhone thermal/hand-feel pass, Compose route
  diagnostics, and a sustained stimulated `core-matrix` comparison before
  changing production defaults. Owns: app stream policy, app model tests,
  physical-device verification note, benchmark artifact.
- **T391** Sustained usability target v2 gate: before changing production app
  defaults, promote the benchmark practical gate from the first v1 floor to an
  explicit `iphone-sustained-usability-v2` target covering controlled-stimulus
  content FPS, average update latency, post-warm-up p95, client-processing p95,
  renderer full-upload pressure, adaptive pressure, Compose route diagnostics,
  and the physical iPhone 10 minute thermal/hand-feel pass. Add
  `--stream-shape-practical-target`, keep v1 available for legacy artifact
  comparison, record a redacted v35 `zrle-isolation` run, and use v2 as the
  default gate for T390 and subsequent cadence/default changes. Owns:
  benchmark kit/CLI/tests, benchmark docs/artifact, research note. **Done.**
- **T392** App-side startup preflight foundation: add an injectable,
  off-by-default app stream startup preflight policy that can consume at most
  one hidden post-first-frame incremental update after the first visible frame
  has already been published. Prove with fake-stream app model tests that the
  hidden frame is requested but not surfaced through framebuffer state or stream
  stats, and that the next visible incremental frame still continues normally.
  Keep production defaults unchanged until T390's physical iPhone gate passes.
  Owns: app stream policy, app model tests, benchmark artifact, research note.
  **Done.**
- **T393** Interaction v2 preflight before physical gate: after real-device
  feedback still reported stepped zoom/pan and unreliable Compose, treat smooth
  viewport/input as one larger unit under `iphone-sustained-usability-v2`.
  Strengthen zoomed trackpad cursor-follow pan while preserving finger-paced
  visible cursor travel, keep SwiftUI/PiP viewport mirroring out of the touch
  hot path until gesture end, and widen marked-text Compose Send stabilization
  so delayed IME commits have more room to settle before paste dispatch. Owns:
  pointer resolver tuning/tests, Metal viewport host, RemoteInputDock sync
  tests, benchmark artifact, research note. **Done.**
- **T394** Compose Send preparation diagnostics for T390: after T393 widened
  marked-text stabilization, expose safe diagnostic JSON v24 fields for the
  latest Compose Send preparation mode, bounded snapshot count, and timing
  bucket so physical iPhone tests can tell whether perceived send delay comes
  from fast snapshots or marked-text stabilization. Do not export draft text,
  raw timings, IME contents, host identity, or coordinates. Owns: Core
  diagnostic schema/tests, RemoteInputDock callback, app model diagnostic
  plumbing/tests, benchmark artifact, research note. **Done.**
- **T395** Sustained session diagnostic gate: add a top-level diagnostic JSON
  v25 `sustainedSessionAssessment` that folds active-session stream metrics,
  thermal state, viewport pressure hints, and Compose route/preparation state
  into fixed target/verdict/issue-code fields for
  `iphone-sustained-usability-v2`. Use exact FPS only in memory to choose safe
  issue codes; do not export raw FPS, raw timings, host identity, dimensions,
  coordinates, pixels, byte counts, draft text, or IME state. Owns: Core
  diagnostic schema/tests, app stats/export wiring, benchmark artifact,
  research note. **Done.**
- **T396** Settings-backed startup preflight experiment gate: expose the
  off-by-default one-hidden-frame app startup preflight as an explicit persisted
  viewer setting, wire it into live app stream policy when no test override is
  injected, and bump diagnostic JSON to v26 with safe startup preflight mode,
  requested/consumed hidden-frame counts, and fixed outcome labels. Keep
  production default disabled until T390 physical iPhone evidence passes; do
  not export hidden frame contents, hidden frame timings, host identity,
  dimensions, coordinates, pixels, byte counts, raw FPS, raw errors, draft
  text, marked text, or IME state. Owns: AppSettings, session controls, app
  stream policy, diagnostics/tests, benchmark artifact, research note.
  **Done.**
- **T397** Stream-shape hit-rate diagnostics: bump `VNCLiveBenchmark` to
  schema v36 with safe aggregate attempted/received/content/empty/unanswered
  sample hit-rate permille fields, propagate content hit-rate into profile
  aggregates/recommendations, and document how these ratios split low content
  FPS into unanswered-request, empty-response, or slow-content-response
  categories before the next cadence/default change. Owns: benchmark summary
  kit, CLI report output, tests, benchmark docs/artifact, research note.
  **Done.**
- **T398** Stream-shape profile gates: bump `VNCLiveBenchmark` to schema v37
  with top-level per-profile/transport practical target gates that summarize
  pass/warning/fail/disabled run counts, fixed issue-code unions, and aggregate
  hit-rate permille means so larger cadence/default/profile changes have a
  single benchmark decision surface before physical iPhone verification. Owns:
  benchmark summary kit, CLI report output, tests, benchmark docs/artifact,
  research note. **Done.**
- **T399** Practical usability baseline goals: consolidate the next work from
  small tuning increments into a larger `iphone-sustained-usability-v2` gate by
  recording a current simulator frame-pipeline baseline, declaring profile-gate
  pass/warning/fail interpretation as the first large-unit decision surface,
  and making physical iPhone 10 minute hand-feel/thermal verification required
  before production streaming defaults change. Use the baseline to steer the
  next implementation unit toward live stream hit-rate, request cadence,
  encoding profile, or physical-device thermal behavior rather than renderer
  upload alone. Owns: benchmark artifact, benchmark README, research note.
  **Done.**
- **T400** Live benchmark environment preflight: add a redacted
  `VNCLiveBenchmark --environment-preflight` report that exits before any VNC
  connection or password prompt, reports fixed host/port/credential/stimulus
  readiness labels plus stable issue codes, supports JSON for diagnostic
  collection, and keeps host identity, credential values, port value, and
  stimulus command text out of output. Owns: benchmark kit model/tests, CLI
  option/output, benchmark docs/artifact, research note. **Done.**
- **T401** Sustained v2 gate preset: add a standard
  `VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-core` CLI preset
  that fixes the controlled-stimulus core matrix, both transport modes, five
  rotated iterations, app client-pressure/viewport pacing, ten second
  duration, zero hidden preflight frames, and schema v38 preset reporting so
  larger optimization PRs use one repeatable gate shape before physical iPhone
  verification. Owns: benchmark kit enum/tests, CLI option/report output,
  benchmark docs/artifact, research note. **Done.**
- **T402** Benchmark-only pixel-format isolation gate: add
  `VNCLiveBenchmark --stream-shape-profiles pixel-format-isolation` and
  `--stream-shape-gate-preset sustained-v2-pixel-format`, using benchmark-only
  RGB565-in-32 SetPixelFormat profile pairs under the same sustained v2
  controlled-stimulus gate shape. Keep app defaults unchanged until live and
  physical-device artifacts show a clear win. Owns: pixel-format constants,
  network-client SetPixelFormat preference, benchmark profile selection,
  gate preset/tests, benchmark docs/artifact, research note. **Done.**
- **T403** Settings-backed app stream profile experiment gate: add a
  fixed-catalog `streamEncodingMode` setting that defaults to standard,
  cycles through benchmark candidates (`zrle-compression-0`,
  `adaptive-good-full`) before connection, lets power saver remain the
  stronger thermal override, and records only the safe fixed label in
  diagnostic schema v27. Owns: app settings, app model, session controls,
  diagnostics, focused tests, benchmark artifact, research note. **Done.**
- **T404** Physical iPhone interaction triage surface: promote the app-side
  sustained-session diagnostic gate from a flat issue-code list to a larger
  decision surface with fixed `primaryIssueCode`, `primaryConstraint`, and
  `recommendedNextProbe` labels. This lets real-device reports choose the next
  large unit between thermal, viewport interaction, renderer/app/decode,
  stream profile/cadence, adaptive pacing, Compose input, or longer physical
  sampling without exporting raw FPS, raw timings, host identity, dimensions,
  coordinates, pixels, byte counts, draft text, marked text, or IME state.
  Owns: diagnostic schema/tests, benchmark docs/artifact. **Done.**
- **T405** Live benchmark practical triage parity: bump `VNCLiveBenchmark` to
  schema v40 and extend each stream-shape `practicalAssessment` with derived
  `primaryIssueCode`, `primaryConstraint`, and `recommendedNextProbe` labels
  using the same sustained-session triage catalog as app diagnostics. Use this
  to make benchmark gates and physical iPhone reports choose the same next
  large optimization unit without exporting host identity, dimensions,
  coordinates, pixels, cursor pixels, byte counts, raw timings, TCP/RFB errors,
  raw payloads, draft text, marked text, or IME state. Owns: benchmark summary
  kit/tests, CLI schema/help, benchmark docs/artifact, research note. **Done.**
- **T406** Report-level benchmark optimization decision: bump
  `VNCLiveBenchmark` to schema v41, aggregate practical triage labels into
  `streamShapeProfileGates`, and add top-level
  `streamShapeOptimizationDecision` so multi-profile benchmark reports choose
  the next large unit before profile recommendations. Emit only fixed gate
  counts, fixed issue/constraint/next-probe labels, and aggregate label counts;
  do not export host identity, dimensions, coordinates, pixels, cursor pixels,
  byte counts, raw timings, TCP/RFB errors, raw payloads, draft text, marked
  text, or IME state. Owns: benchmark summary kit/tests, CLI schema/text
  report, benchmark docs/artifact, research note. **Done.**
- **T407** Gate-level benchmark failure-label routing: bump
  `VNCLiveBenchmark` to schema v42 and lift existing safe stream-shape
  `failureLabel` values into `failureLabelCounts` on
  `streamShapeProfileGates` and `streamShapeOptimizationDecision`. Use the
  redacted sustained-v2-core live baseline to route the next large unit toward
  server transport/cadence inspection, while keeping raw TCP/RFB errors, host
  identity, dimensions, coordinates, pixels, cursor pixels, byte counts, raw
  timings, raw payloads, command text, command output, draft text, marked text,
  and IME state out of reports. Owns: benchmark summary kit/tests, CLI
  schema/text report, benchmark docs/artifact, research note. **Done.**
- **T408** Report-level transport/cadence diagnosis: bump
  `VNCLiveBenchmark` to schema v43 and add
  `streamShapeTransportCadenceDiagnosis` with fixed per-transport status labels,
  aggregate blocked/total gate counts, per-transport constraint/failure-label
  counts, a recommended transport label, and a fixed next-action label. Use the
  v42 sustained-v2-core live baseline to route repeated ContinuousUpdates
  connection failures to `inspectContinuousUpdatesConnection` while preserving
  request-response as the current usable transport. Do not export host
  identity, dimensions, coordinates, pixels, cursor pixels, byte counts, raw
  timings, raw TCP/RFB errors, raw payloads, command text, command output,
  draft text, marked text, or IME state. Owns: benchmark summary kit/tests, CLI
  schema/text report, benchmark docs/artifact, research note. **Done.**
- **T409** Sustained usability operating target: define the larger-unit
  promotion ladder for upcoming streaming work. A candidate must first reach a
  benchmark-green v43 decision surface, then pass a 10 minute physical iPhone
  hand-feel/thermal/Compose diagnostic gate, and only then change production
  transport, encoding, preflight, pacing, or interaction defaults. Keep the
  current non-green status explicit: request-response is the usable fallback,
  ContinuousUpdates needs connection/receive inspection, and no production
  default should change from the current benchmark evidence alone. Owns:
  benchmark artifact, README, research note. **Done.**
- **T410** ContinuousUpdates support-confirmation gate: require an active RFB
  session to observe the server's ContinuousUpdates confirmation before sending
  `EnableContinuousUpdates`, keep the frame pump on request/response until that
  happens, and make `VNCLiveBenchmark` report the fixed safe label
  `stream-continuous-updates-continuous-updates-not-confirmed` instead of
  silently measuring request/response fallback under the ContinuousUpdates
  transport label. Keep production ContinuousUpdates off by default and keep raw
  TCP/RFB details out of diagnostics and benchmark reports. Owns: network client,
  frame pump capability boundary, app diagnostic mapping, benchmark failure
  labels/summary tests, fake-server tests, benchmark docs/artifact, research
  note. **Done.**
- **T411** Physical gate verdict for larger interaction units: bump diagnostic
  collection schema to v29 and add `physicalGateVerdict` to
  `sustainedSessionAssessment`. The detailed assessment `verdict` may remain
  `warning` for non-fatal triage, but `physicalGateVerdict` is `pass` only when
  no sustained-session issue code is present; any viewport, Compose, thermal,
  renderer, receive, cadence, adaptive, or sample-size issue blocks production
  default promotion. Owns: diagnostic schema/tests, app export test, benchmark
  docs/artifact, research note. **Done.**
- **T412** Physical sustained candidate gate runner: extend the physical iPhone
  UI test from connect-only smoke to an opt-in sustained candidate gate that
  injects fixed stream power / encoding / startup-preflight labels, performs
  viewport pinch-pan, zoomed trackpad movement, and a Compose Send attempt, and
  emits delayed active-session diagnostic JSON through `makeDiagnosticExport()`.
  Use the final safe `physicalGateVerdict` plus manual hand-feel notes before
  promoting app defaults; do not export host identity, credentials, device id,
  screenshots, raw text, raw timings, dimensions, coordinates, pixels, or
  command output. Owns: physical UI test, iOS app test hook, app diagnostic
  emission hook, benchmark docs/artifact, research note. **Done.**
- **T413** Sustained usability candidate contract: consolidate the next larger
  optimization units around a whole-candidate merge contract for
  `iphone-sustained-usability-v2`. A production-default change must name fixed
  candidate labels, pass the redacted benchmark gate, pass the 10 minute
  physical iPhone hand-feel/thermal/Compose gate, and include a rollback note.
  Remediation labels route the next larger unit instead of authorizing defaults,
  and the contract artifact is the source of truth for those promotion
  requirements. Owns: benchmark artifact, README, spec/plan links, research
  note. **Done.**
- **T414** Live preflight action hints: bump environment preflight schema to v2
  with fixed setup action labels so missing host, credential, port, or stimulus
  setup routes to the next safe operator action before the sustained v2 live
  gate runs. Keep v1 JSON decodable and do not expose host identity,
  credentials, port values, stimulus command text, raw TCP/RFB errors, or
  command output. Owns: benchmark kit, CLI text output, tests, README,
  benchmark artifact, research note. **Done.**
- **T415** Completed live sustained-v2-core baseline: after preflight can reach
  `run-live-gate`, run the redacted live gate against the local private VNC
  target and record the large-unit decision surface. Keep the current result
  explicit: all sustained v2 gates still fail, ContinuousUpdates is
  `failed-before-samples`, request/response is the fallback but remains
  `below-target`, and the next large unit is ContinuousUpdates
  confirmation/receive inspection before any production default promotion.
  Owns: benchmark artifact, README, research note. **Done.**
- **T416** Request/response sustained-v2 preset: add a benchmark-only
  `sustained-v2-request-response` gate preset that keeps the same controlled
  stimulus, core matrix, iterations, pacing, pressure, viewport interaction,
  duration, preflight, and target shape as `sustained-v2-core` while measuring
  request/response transport only. Use it for larger request/response profile
  and cadence comparisons after ContinuousUpdates has already routed to
  inspection. Do not change production defaults or weaken the full promotion
  gate. Owns: benchmark CLI preset, tests, README, benchmark artifact, research
  note. **Done.**
- **T417** Request/response preset skips standalone ContinuousUpdates probe:
  allow `--continuous-update-samples 0`, report a fixed `not-tested` status for
  zero-sample standalone ContinuousUpdates probes, and make
  `sustained-v2-request-response` set that count to 0. This keeps
  request/response-only candidate comparisons free of known ContinuousUpdates
  blocker noise without weakening the full `sustained-v2-core` promotion gate.
  Owns: benchmark CLI/report status, README, benchmark artifact, research note.
  **Done.**
- **T418** Controlled stimulus cadence target: bump `VNCLiveBenchmark` to schema
  v44 with a reported `streamShapeStimulusFrameIntervalSeconds` and
  `streamShapeStimulusExpectedFramesPerSecond`, pass the same fixed cadence to
  external stimulus children via `NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS`,
  and make `VNCLiveStimulusWindow` consume that value by default. This pins the
  sustained v2 controlled stimulus at 12 Hz so future low content-FPS results
  can be routed to server/transport/profile cadence inspection instead of
  ambiguous stimulus suspicion. Owns: benchmark CLI/report, benchmark-kit
  environment tests, stimulus helper, README, benchmark artifact, research
  note. **Done.**
- **T419** Steady-stream sustained v2 gate alignment: keep the
  `sustained-v2-*` benchmark presets as steady-stream gates by disabling
  viewport-interaction parity inside the presets, while leaving active
  viewport-interaction stream pressure to custom benchmark commands and the
  physical iPhone promotion gate. This keeps the 8fps controlled-stimulus target
  from being capped by the app's intentional 4Hz-class local-gesture pacing
  floor. Owns: benchmark CLI preset, README, benchmark artifact, research note.
  **Done.**
- **T420** Request/response ZRLE isolation preset: add a benchmark-only
  `sustained-v2-zrle-isolation` gate preset that keeps the sustained v2
  request/response shape, selects `zrle-isolation`, skips the standalone
  ContinuousUpdates probe, and emits schema v45 so the new fixed preset label is
  explicit in live reports. Record the first redacted live result and route the
  next large unit to server/request-response cadence when pure ZRLE removes
  client-decode tail but still misses the 8fps steady-stream target. Owns:
  benchmark CLI preset, tests, README, benchmark artifact, research note.
  **Done.**
- **T421** Request/response zero-delay cadence gate: add a benchmark-only
  `sustained-v2-zrle-zero-delay` preset that reuses the ZRLE isolation shape
  with `streamShapeFrameIntervalSeconds=0`, emits schema v46 for the new fixed
  preset label, and records a redacted live result. Update transport/cadence
  diagnosis so receive-path-majority mixed failures route to
  `tuneTransportCadence` rather than another encoding-profile comparison. Owns:
  benchmark CLI preset, transport diagnosis tests, README, benchmark artifact,
  research note. **Done.**
- **T422** Request cadence health report: bump `VNCLiveBenchmark` to schema v47
  with a top-level `streamShapeRequestCadenceHealth` report derived only from
  request/response profile aggregates and gates. Split request cadence triage
  into fixed sample-hit status, fixed aggregate latency status, fixed next
  probe label, aggregate request/response gate/run counts, aggregate permille
  ratios, and aggregate millisecond summaries. Use the live zero-delay gate to
  prove the current blocker is high content hit with p95 request/update tail,
  not unanswered waits or empty responses. Do not export host identity,
  dimensions, coordinates, pixels, cursor pixels, byte counts, raw timings, raw
  TCP/RFB errors, raw payloads, command text, command output, draft text, marked
  text, or IME state. Owns: benchmark summary kit/tests, CLI schema/text
  report, README, benchmark artifact, research note. **Done.**
- **T423** Request pacing window sweep gate: bump `VNCLiveBenchmark` to schema
  v48 with fixed `streamShapePacingWindows` labels on stream-shape probes,
  aggregates, gates, and recommendations. Add the benchmark-only
  `sustained-v2-zrle-pacing-sweep` preset that holds
  `zrle-compression-0-clipboard` constant, uses request/response only, rotates
  `zero-content-delay`, `app-balanced-30hz`, and `stimulus-aligned-12hz` for 5
  iterations, and records a redacted live result. Keep older profile reports
  decoding as `single`, keep pacing windows separate in aggregates/gates, and
  do not export host identity, dimensions, coordinates, pixels, cursor pixels,
  byte counts, raw timings, raw TCP/RFB errors, raw payloads, command text,
  command output, draft text, marked text, or IME state. Owns: pacing policy
  kit/tests, benchmark summary kit/tests, CLI schema/text report, README,
  benchmark artifact, research note. **Done.**
- **T424** Request/update phase budget diagnostics: bump `VNCLiveBenchmark` to
  schema v49 with safe aggregate `phaseBudget` summaries that split measured
  update duration into request-loop, network-read, and client-processing shares.
  Surface dominant and slow-tail dominant phases on profile summaries,
  aggregates, and request cadence health so high-hit p95 failures route to
  update-wait inspection when the tail is outside decode/render pressure. Keep
  older summaries decoding with an empty phase budget and do not export host
  identity, dimensions, coordinates, pixels, cursor pixels, byte counts, raw
  timings, raw TCP/RFB errors, raw payloads, command text, command output, draft
  text, marked text, or IME state. Owns: benchmark summary kit/tests, CLI
  schema/text report, README, benchmark artifact, research note. **Done.**
- **T425** First-byte wait split diagnostics: bump `VNCLiveBenchmark` to schema
  v50 and split measured network-read time into first-byte wait and payload-read
  subphases. Surface fixed subphase labels, subphase latency summaries, and
  network-read split permille ratios on stream-shape summaries, profile
  aggregates, and request cadence health so the v49 network-read tail can be
  routed to server/update-production work instead of socket payload read work.
  Keep older reports decoding safely and do not export host identity, dimensions,
  coordinates, pixels, cursor pixels, byte counts, raw timings, raw TCP/RFB
  errors, raw payloads, command text, command output, draft text, marked text, or
  IME state. Owns: core receive timing, benchmark summary kit/tests, CLI
  schema/text report, README, benchmark artifact, research note. **Done.**
- **T426** Incremental request-region sweep gate: add a region-capable
  `FramebufferUpdateRequest` boundary, keep the first frame full-screen, and
  let the frame pump pass a benchmark-only incremental request region to
  request/response and ContinuousUpdates paths. Bump `VNCLiveBenchmark` to
  schema v51 with fixed `streamShapeRequestRegions` labels on probes,
  aggregates, gates, and recommendations, plus a
  `sustained-v2-zrle-region-sweep` preset that holds
  `zrle-compression-0-clipboard` constant and compares `full`, `center-half`,
  and `center-third` without emitting coordinates or dimensions. Record the
  first redacted live result and route the next large unit away from naive
  static regions toward viewport-aware region selection with full-frame
  fallback/heartbeat. Owns: core request boundary, frame pump, benchmark kit,
  CLI schema/text report, fake-server tests, README, benchmark artifact,
  research note. **Done.**
- **T427** Viewport-aware request-region foundation: stop treating region
  narrowing as static center rectangles. Add a pure `ViewportTransform` ->
  `RFBFramebufferUpdateRegion` policy with expansion margin, minimum savings
  threshold, full-frame heartbeat, and timeout-to-full fallback; add fixed
  benchmark labels for representative phone-portrait viewport regions; and add
  a `sustained-v2-zrle-viewport-region` preset that compares full requests
  against viewport-aware candidates without emitting coordinates, dimensions,
  pixels, byte counts, host identity, raw timings, raw TCP/RFB errors, command
  text, draft text, marked text, or IME state. Keep production app defaults on
  full incremental requests until the sustained v2 benchmark and physical
  iPhone gate pass. Owns: Core viewport policy/tests, benchmark kit/CLI,
  README, benchmark artifact, research note. **Done.**
- **T428** Traffic-pressure promotion metric: make poor-network usability a
  first-class benchmark target without exporting raw byte counts. Bump
  `VNCLiveBenchmark` to schema v53, add safe `requestRegionAreaPermille`
  reporting on profile probes, aggregates, gates, and text output, and record
  the FR-016 / SC-007 rule that request-region defaults require both traffic
  pressure reduction and unchanged-or-better stream stability. Owns: benchmark
  request-region kit/tests, summary kit/tests, CLI schema/text report, README,
  spec/research notes. **Done.**
- **T429** Incremental request timeout recovery: preserve the active RFB
  connection when an incremental request times out before reading any server
  bytes, return a zero-change idle frame, and let viewport-region benchmark
  probes immediately recover with a full fallback request on the same socket.
  Keep non-incremental and partial-message timeouts fatal, bump
  `VNCLiveBenchmark` to schema v54, and prove the behavior with
  `FakeRFBServer` request scripts before comparing live traffic candidates.
  Owns: `RFBNetworkClient`, `VNCLiveBenchmark`, fake-server tests, README,
  research note. **Done.**
- **T430** Degraded-network benchmark harness: add a benchmark-only local TCP
  conditioning proxy behind `VNCLiveBenchmark --network-condition
  none|wan-latency|constrained-cellular`, bump reports to schema v55 with only
  the fixed condition label, and keep proxy ports/upstream hosts/byte counters
  out of reports. Prove chunk/delay profiles and proxy forwarding with tests
  before using the harness for poor-network request-region comparisons. Owns:
  benchmark kit profile/proxy, CLI/report/help, tests, README, research note,
  benchmark artifact. **Done.**
- **T431** Constrained-cellular bootstrap traffic gate: make poor-network
  traffic an explicit benchmark target by adding
  `iphone-poor-network-traffic-v1`, fixed `first-frame-*` and
  `request-region-area-*` gate issue codes, and the benchmark-only
  `sustained-v2-constrained-cellular-bootstrap` preset. The preset applies
  constrained-cellular conditioning, request/response-only phone viewport
  probes, benchmark-only full-color/RGB565 profile pairs, 30 s startup timeout,
  and schema v56 safe reporting. Record the live result showing full-color
  candidates fail before startup while RGB565 reaches samples but still misses
  the startup target, routing the next large unit to first-visible-region
  bootstrap work before any production default change. Owns: benchmark summary
  kit/tests, CLI preset/help/report schema, README, spec/research notes,
  benchmark artifact. **Done.**
- **T432** First-visible-region startup benchmark: add an opt-in
  `initialRequestRegion` path to `RFBFramePump`, keep the production/default
  first frame full, and let `VNCLiveBenchmark` schema v57 report a fixed
  `streamShapeFirstFrameRequestMode` label. Add
  `sustained-v2-constrained-cellular-visible-startup` so constrained-cellular
  traffic work can compare full-frame startup against first visible phone
  viewport startup without emitting coordinates, dimensions, byte counts,
  pixels, payloads, host identity, command text, draft text, marked text, or
  IME state. Record the live constrained-cellular result and keep any
  production request-region default blocked until benchmark and physical
  iPhone gates pass. Owns: `RFBFramePump`, benchmark kit/CLI/report/help,
  tests, README, research note, benchmark artifact. **Done.**
- **T433** First-visible-core startup traffic gate: add a benchmark-only
  `visible-core` first-frame request mode and
  `sustained-v2-constrained-cellular-visible-core-startup` preset. Bump
  `VNCLiveBenchmark` to schema v58 so profile probes, aggregates, and gates
  report redacted `firstFrameRequestAreaPermille`, and make poor-network
  traffic gates judge the larger of sustained request area and first-frame
  request area without emitting coordinates, dimensions, byte counts, pixels,
  payloads, host identity, command text, draft text, marked text, or IME state.
  Owns: benchmark kit/CLI/report/help, tests, README, research note, benchmark
  artifact. **Done.**
- **T434** First-frame receive timing diagnostics: bump `VNCLiveBenchmark` to
  schema v59 and report redacted first-frame receive timing on profile probes
  and aggregates so startup failures can be separated into first-byte wait,
  payload read, and client processing. Keep the fields to aggregate
  milliseconds and permille shares only, with no coordinates, dimensions, byte
  counts, pixels, payloads, host identity, command text, draft text, marked
  text, or IME state. Record the constrained-cellular visible-core timing
  result and use it to split the next work into startup payload pressure and
  sustained update-wait cadence tracks. Owns: benchmark summary kit/tests, CLI
  report/help, README, research note, benchmark artifact. **Done.**
- **T435** First-visible-focus startup payload gate: after v59 showed
  constrained-cellular RGB565 startup is payload-read dominated and still just
  above the 20 s poor-network gate, add a benchmark-only `visible-focus`
  first-frame request mode and
  `sustained-v2-constrained-cellular-visible-focus-startup` preset. Bump
  `VNCLiveBenchmark` to schema v60, keep sustained incremental requests on the
  existing viewport region/fallback policy, and report only fixed labels plus
  first-frame request-area permille and aggregate receive timing. Keep
  production app startup full-frame until benchmark and physical iPhone gates
  pass. Owns: benchmark first-frame request policy, CLI preset/help, tests,
  README, research note, benchmark artifact. **Done.**
- **T436** Sustained poor-network traffic wait gate: after v60 confirms
  visible-focus reduces startup payload pressure but sustained samples remain
  update-wait dominated, bump `VNCLiveBenchmark` to schema v61 and make the
  poor-network traffic target classify sustained `first-byte-wait-*` and
  `payload-read-*` issue codes from aggregate timing/permille summaries. Keep
  payload-read pressure routed to encoding/traffic comparison and first-byte
  wait routed to server/update-wait timing inspection. Do not emit byte counts,
  dimensions, coordinates, pixels, raw payloads, host identity, command text,
  draft text, marked text, or IME state. Owns: benchmark summary kit/tests,
  CLI report/help, README, research note, benchmark artifact. **Done.**
- **T437** App-side opt-in viewport request regions: wire
  `SessionViewportView`'s memory-only `ViewportTransform` into
  `NaruRemoteAppModel` and pass `ViewportRequestRegionPolicy` output to
  incremental `RFBFramePump.nextFrame` calls only when the user has selected
  the fixed `zrle-compression-0-rgb565` low-traffic stream profile. Keep the
  first frame and standard profile full-frame, retain heartbeat/fallback
  behavior through the shared policy, disable region narrowing when power saver
  overrides the stream profile, and avoid logging/exporting dimensions,
  coordinates, byte counts, pixels, or per-sample timings. Owns: app shell,
  session viewport callback, app-model tests, spec/research note, benchmark
  artifact. **Done.**
- **T438** App low-traffic poor-network benchmark preset: add an
  `app-low-traffic` stream-shape profile selection and
  `sustained-v2-constrained-cellular-app-low-traffic` gate preset that keeps
  the v61 constrained-cellular visible-focus traffic shape but runs only the
  fixed `zrle-compression-0-rgb565` app opt-in profile. Preserve report labels
  as fixed catalog values, update CLI help and benchmark promotion contracts,
  and keep raw dimensions, coordinates, byte counts, pixels, payloads, raw
  errors, command text, draft text, marked text, and IME state out of artifacts.
  Owns: benchmark profile selection, CLI preset, tests, README, research note,
  benchmark artifact. **Done.**
- **T439** Startup payload traffic gate: after the app low-traffic live gate
  showed a small first-frame request area can still spend most startup time in
  payload read, bump `VNCLiveBenchmark` to schema v62 and add
  `first-frame-payload-read-warning` / `first-frame-payload-read-failed` issue
  codes to the poor-network profile gate. Classify first-frame payload-read
  milliseconds and payload-read share permille from aggregate
  `RFBFramebufferUpdateTiming`, route failures to encoding/traffic comparison,
  and preserve the existing privacy boundary: no dimensions, coordinates, byte
  counts, pixels, payloads, raw host identity, command text, draft text, marked
  text, or IME state in reports/artifacts. Owns: benchmark summary kit/tests,
  CLI report/help, README, research note, live benchmark artifact. **Done.**
- **T440** App low-traffic visible-focus first frame: after D108 showed startup
  payload-read pressure dominates the app low-traffic poor-network gate, wire
  the session viewport container size into `NaruRemoteAppModel` and let the
  fixed `zrle-compression-0-rgb565` opt-in profile request a visible-focus
  first-frame region when a safe matching transform or viewport size is
  available. Keep standard profile, power-saver/low-power mode, invalid
  dimensions, and fallback cases full-frame. Document the broader sustained
  iPhone VNC performance plan, keep viewport size / derived request region
  memory-only, and avoid logging/exporting dimensions, coordinates, byte counts,
  pixels, payloads, host identity, command text, draft text, marked text, or IME
  state. Owns: app shell, session viewport callback, app-model tests, research
  artifact, spec/research note. **Done.**
- **T441** App low-traffic visible-glance startup region: after D109 and the
  smaller-area live probe showed visible-focus still spends too long in
  startup payload read, split first-useful-paint from sustained viewport
  streaming. Add a shared centered-scale helper, use a 0.60 visible-core
  startup slice only for the first app low-traffic request, keep sustained
  incremental requests on the existing margin-expanded viewport policy, add a
  fixed benchmark `visible-glance` mode with schema v63, and document the live
  app-candidate gate result. Keep standard profile, power-saver/low-power
  override, mismatched transforms, invalid dimensions, and fallback cases
  full-frame, and avoid logging/exporting dimensions, coordinates, byte counts,
  pixels, payloads, host identity, command text, draft text, marked text, or
  IME state. Owns: core viewport helper/tests, app-model startup policy/tests,
  benchmark first-frame mode/tests/help, README, research note, live benchmark
  artifact. **Done.**
- **T442** App local-low-latency RGB565 candidate: after D111 showed
  `local-low-latency-rgb565` beats `zrle-compression-0-rgb565` on sustained
  content hit rate, p95 update latency, client-processing tail, and renderer
  full-upload pressure under the visible-glance poor-network harness, add it
  as an app opt-in stream mode. Wire it to `.localLowLatency` plus
  `.rgb565In32LittleEndian`, include it in the stream-profile toggle before
  ZRLE compression 0, apply the same viewport-aware low-traffic request policy,
  update app-low-traffic benchmark selection to compare both app RGB565
  candidates, and document the live v63 preset result. Keep standard as the
  production default and avoid logging/exporting dimensions, coordinates, byte
  counts, pixels, payloads, host identity, command text, draft text, marked
  text, or IME state. Owns: app settings, app model, session viewer label,
  benchmark profile selection/preset/help, tests, README, research note, live
  benchmark artifact. **Done.**
- **T443** App low-traffic glance scale tuning: after D112 showed the 0.60
  visible-glance startup still spends too long in first-frame payload read,
  reduce the shared app/benchmark startup glance scale to 0.45. Keep sustained
  requests on the existing margin-expanded viewport-aware policy, explicitly
  reject the timed-out two-phase non-incremental viewport hydration experiment,
  and document the v63 live run where first-frame request area drops to
  61 permille while both app RGB565 candidates keep 4/4 sustained content
  samples and 0 permille renderer full-upload pressure. Keep standard as the
  production default and avoid logging/exporting dimensions, coordinates, byte
  counts, pixels, payloads, host identity, command text, draft text, marked
  text, or IME state. Owns: app startup scale, benchmark request-region scale,
  tests, README, research note, live benchmark artifact. **Done.**
- **T444** Benchmark-only visible-glance scale sweep: after D113 showed 0.45
  still fails the poor-network gate on first-frame payload-read pressure, add a
  v64 live benchmark override for visible-glance startup scale so 0.35/0.25 can
  be measured without changing product code. Emit only a clamped scale permille
  plus existing fixed labels and area-permille metrics, keep product app
  default at 0.45 until device visual inspection proves a smaller patch is
  recognizable, and document the live v64 runs where 0.25 reduced first-frame
  area to 19 permille and payload read to about 5.1 s while both app RGB565
  candidates kept 4/4 sustained content samples and 0 permille renderer
  full-upload pressure. Avoid logging/exporting dimensions, coordinates, byte
  counts, pixels, payloads, host identity, command text, draft text, marked
  text, or IME state. Owns: benchmark request-region override, first-frame
  mode plumbing, CLI/report schema/help, tests, README, research note, live
  benchmark artifact. **Done.**
- **T445** Synthetic first-frame visual audit: after D114 separated startup
  traffic wins from recognizable first-useful-paint quality, add a v65
  `visible-glance` audit that reports only synthetic terminal-grid axis/area
  coverage permille values, omitted-area permille, a fixed risk label, and a
  `visualCheckRequired` boolean. Use it to mark 0.25 as a `glance-only`
  candidate before any product-default change, even though the v65 live run
  improved the poor-network traffic verdict to `warning` with about 4.9 s
  first-frame payload read. Avoid logging/exporting live pixels, dimensions,
  coordinates, byte counts, payloads, host identity, command text, draft text,
  marked text, or IME state. Owns: benchmark report schema/help/text output,
  benchmark-kit tests, README, research note, live benchmark artifact. **Done.**
- **T446** Opt-in app startup glance scale setting: after D115 kept 0.25 as a
  visual-risk candidate, add a persisted non-secret setting that cycles
  low-traffic RGB565 startup glance scale through 0.45, 0.35, and 0.25 before
  connection. Apply it only to the first non-incremental viewport-aware
  low-traffic request, keep product default at 0.45, expose the toggle only
  while inactive and relevant, and include only the fixed enum label in
  diagnostic schema v30. Avoid logging/exporting live pixels, dimensions,
  coordinates, byte counts, payloads, host identity, command text, draft text,
  marked text, or IME state. Owns: app settings, app model stream region
  policy, session control, diagnostic schema/tests, README, research note.
  **Done.**
- **T447** Physical glance candidate gate coverage: after D116 found the
  physical sustained candidate gate could not directly launch the new
  low-traffic RGB565 startup-glance candidates, add the test-only startup
  glance scale override, accept `local-low-latency-rgb565` /
  `zrle-compression-0-rgb565` and `standard-045|minimal-035|glance-025` in the
  physical gate environment, record only the fixed candidate label in the
  configuration attachment, and add a simulator UI regression that proves the
  glance button stays hidden for standard streams but appears and cycles for a
  low-traffic candidate. Do not change production defaults and avoid
  logging/exporting host identity, credentials, device id, screenshots, raw
  logs, dimensions, coordinates, pixels, byte counts, draft text, marked text,
  or IME state. Owns: iOS app test hook, physical UI test, launch UI test,
  README, research note, benchmark artifact. **Done.**
- **T448** Request/response pipeline-depth live benchmark: after D117 and the
  constrained-cellular app-low-traffic gate showed sustained samples dominated
  by server/network first-byte wait, add a benchmark-only send-only
  `FramebufferUpdateRequest` boundary and `VNCLiveBenchmark` schema v66
  `--stream-shape-request-pipeline-depth 1...3`. Keep depth 1 as the existing
  baseline, reject depth >1 with ContinuousUpdates, leave production app frame
  delivery unchanged, and document how to compare depth 1/2/3 using the live
  password only through `NARU_LIVE_MAC_PASSWORD`. Report only the clamped depth
  integer plus existing aggregate timing/permille metrics; avoid
  logging/exporting outstanding-request coordinates, dimensions, byte counts,
  pixels, payloads, host identity, credentials, command text, draft text,
  marked text, or IME state. Owns: core RFB client boundary, network client,
  benchmark CLI/report, fake-server test, help text, research note, benchmark
  artifact. **Done.**
- **T449** Launchctl request-pipeline sweep runner: add a launchctl-backed
  `request-pipeline-sweep` mode that reruns the constrained-cellular
  app-low-traffic VNC shape at request pipeline depths 1, 2, and 3 without
  printing host, credential, helper path, request rectangles, bytes, pixels, or
  raw errors. Reject caller-supplied pipeline-depth overrides so each run is a
  real sweep, and record the v66/v67 live result showing no depth clears the
  poor-network target. Owns: launchctl runner script, README, research note,
  benchmark artifact. **Done.**
- **T450** Bounded launchctl VNC profile sweep: add a live runner mode for the
  fixed `tight-first,zrle-compression-0,adaptive-good-full` candidate set with a
  script-level wall-clock guard and fixed timeout JSON, so long live sweeps do
  not block sustained-usability work or print unsafe diagnostics. Owns:
  launchctl runner, benchmark docs/artifact. **Done.**
- **T451** Bounded sweep phase attribution: split the launchctl-backed
  `bounded-vnc-profile-sweep` runner into fixed `swift-build` and
  `benchmark-running` phases, include only catalog `lastPhaseLabel` values on
  guarded timeout/failure JSON, and record the current live timeout as reaching
  benchmark execution. Do not print or export command lines, executable paths,
  host identity, credentials, ports, raw stdout/stderr, TCP/RFB errors,
  coordinates, dimensions, pixels, byte counts, stimulus text, draft text,
  marked text, or IME state. Owns: launchctl runner, README, research note,
  benchmark artifact. **Done.**
- **T452** Bounded VNC profile drilldown runner: add a launchctl-backed mode
  that builds `VNCLiveBenchmark` once, runs the fixed
  `tight-first,zrle-compression-0,adaptive-good-full` candidates one at a time
  with per-profile wall-clock guards, rejects caller overrides for managed
  benchmark dimensions, and records whether failures are profile-specific or
  shared across candidates. Emit only catalog profile labels, fixed ordinals,
  fixed phase labels, fixed safe failure labels, and successful benchmark JSON;
  avoid host identity, credentials, ports, executable paths, command lines,
  raw stdout/stderr, raw TCP/RFB errors, request coordinates, dimensions,
  pixels, byte counts, stimulus command text, draft text, marked text, or IME
  state. Owns: launchctl runner, README, research note, benchmark artifact.
  **Done.**
- **T453** Safe benchmark subphase progress for bounded live failures: add a
  `VNCLiveBenchmark` progress-file option that writes only fixed subphase labels
  and safe catalog profile labels to a runner-owned temp file, surface those
  labels only on bounded timeout/failure JSON, and remove the bounded runner's
  `sustained-v2-core` preset override so explicit candidate profiles are
  actually measured. Record the corrected live bounded evidence and the
  previous all-timeout result as superseded by the runner configuration fix.
  Do not print/export progress paths, executable paths, command lines, host
  identity, credentials, ports, raw stdout/stderr, TCP/RFB errors, coordinates,
  dimensions, pixels, byte counts, stimulus command text, draft text, marked
  text, or IME state. Owns: benchmark CLI, launchctl runner, README, research
  note, benchmark artifact. **Done.**
- **T454** Bounded VNC warning-candidate stability runner: add a
  launchctl-backed mode that repeats the corrected warning candidates
  `tight-first` and `adaptive-good-full` with order rotation before any
  production-default promotion. Reject caller overrides for managed benchmark
  dimensions, record the current live stability result, and keep `tight-first`
  as only a working candidate until client-decode/content-cadence pressure is
  reduced. Emit only privacy-safe benchmark JSON or fixed runner failure labels;
  do not print/export host identity, credentials, ports, executable paths,
  command lines, raw stdout/stderr, raw TCP/RFB errors, coordinates, dimensions,
  pixels, byte counts, stimulus command text, draft text, marked text, or IME
  state. Owns: launchctl runner, README, research note, benchmark artifact.
  **Done.**
- **T455** Tight-first RGB565 negative-candidate check: add benchmark-only
  `tight-first-rgb565`, include it in the pixel-format isolation catalog and
  bounded candidate-stability runner, then record the live result showing it is
  not better than full-color `tight-first` under the current sustained iPhone
  target. Keep production app stream modes unchanged and use the result to move
  the next optimization unit toward request/response cadence and server
  first-byte wait. Emit only fixed profile labels, fixed verdict/issue labels,
  aggregate counts, permille ratios, and aggregate timings; do not print/export
  host identity, credentials, ports, executable paths, command lines, raw
  stdout/stderr, raw TCP/RFB errors, coordinates, dimensions, pixels, byte
  counts, stimulus command text, draft text, marked text, or IME state. Owns:
  benchmark profile catalog, launchctl runner, profile-selection tests,
  README, research note, benchmark artifact. **Done.**
- **T456** Tight-first cursor benchmark candidate: add benchmark-only
  `tight-first-cursor` and `tight-first-cursor-clipboard`, plus a
  launchctl-backed bounded runner that compares `tight-first` against
  `tight-first-cursor` for trackpad-friendly server-cursor evidence. Record the
  live result showing `tight-first-cursor` keeps warning-only gates, 6/6 content
  samples, lower average/p95 update latency, and 0 permille renderer full-upload
  pressure, while the clipboard variant is not ready because it increases
  client-processing pressure. Keep production app stream modes unchanged until
  a longer sustained or physical iPhone run supports an opt-in. Emit only fixed
  profile labels, fixed verdict/issue labels, aggregate counts, permille ratios,
  and aggregate timings; do not print/export host identity, credentials, ports,
  executable paths, command lines, raw stdout/stderr, raw TCP/RFB errors,
  coordinates, dimensions, pixels, byte counts, stimulus command text, draft
  text, marked text, or IME state. Owns: benchmark profile catalog, launchctl
  runner, README, research note, benchmark artifact. **Done.**
- **T457** Tight-first cursor request pipeline depth sweep: add a
  launchctl-backed bounded runner that builds `VNCLiveBenchmark` once and runs
  fixed `tight-first-cursor` at request pipeline depths 1, 2, and 3 with a
  longer 12-sample / 10-second sustained shape. Record the live result showing
  depth 1 remains the best product candidate, depth 2 does not improve the p95
  tail or content cadence enough, and depth 3 fails from client-processing
  pressure. Keep production request pipeline depth at 1. Emit only fixed
  mode/profile labels, fixed verdict/issue labels, depth integers, aggregate
  counts, permille ratios, and aggregate timings; do not print/export host
  identity, credentials, ports, executable paths, command lines, raw
  stdout/stderr, raw TCP/RFB errors, coordinates, dimensions, pixels, byte
  counts, stimulus command text, draft text, marked text, or IME state. Owns:
  launchctl runner, README, research note, benchmark artifact. **Done.**

## Cross-cutting (every increment)

- No pixel/coord/tile/palette/byte-count/latency/JPEG/cursor data in any log or
  diagnostic export (constitution §IV / SP-005); decode hot path has zero logging.
- Decoders are trap-free and allocation-bounded against hostile server bytes (SP-006).
- iPhone path verified before any iPad path (constitution §VI).
- Protocol claims proven against `FakeRFBServer`/crafted fixtures before "done"; real
  servers are residual-risk device tasks (constitution §III).
