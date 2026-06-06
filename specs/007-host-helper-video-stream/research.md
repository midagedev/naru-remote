# Research: Host Helper Video Stream

## D1 - Treat helper video as the next path after RFB request tuning

**Decision**: Start a separate helper-video feature instead of adding more
request pacing variants to the VNC-only path.

**Rationale**:
- RFC 6143 permits multiple outstanding `FramebufferUpdateRequest` messages,
  but the live request-pipeline benchmark showed depth 2/3 did not improve the
  constrained-cellular first-byte tail.
- The current best VNC candidate already uses low-traffic RGB565, small
  first-visible startup slices, viewport-aware sustained regions, renderer
  partial-upload behavior, and app-side client-pressure pacing.
- Remaining startup payload and sustained first-byte wait are now tied to the
  VNC server/update source and framebuffer representation. A helper video
  source changes that representation.

**Sources**:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- `artifacts/benchmarks/2026-06-06-request-pipeline-benchmark-summary.md`
- `specs/004-rfb-encodings/research.md` D117

**Alternatives considered**:
- Deeper request burst: rejected because depth 2/3 did not help and may add
  useless server work.
- More aggressive startup crop as the only path: kept as an opt-in VNC
  candidate, but it risks unreadable first paint and does not solve sustained
  first-byte wait.

## D2 - Use ScreenCaptureKit for Mac helper capture

**Decision**: The first Mac helper video prototype should use ScreenCaptureKit
for capture in the logged-in user's session.

**Rationale**:
- Apple documents ScreenCaptureKit as the framework for high-performance screen
  and audio capture in Mac apps.
- ScreenCaptureKit screen streams deliver `CMSampleBuffer` values with media
  data and metadata, which fits a VideoToolbox encode pipeline.
- The permission boundary is explicit and user-visible through macOS Screen
  Recording permission.

**Sources**:
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple Capturing screen content in macOS: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos

**Alternatives considered**:
- CGDisplayStream or screenshot polling: rejected for the first milestone
  because the product needs a streaming path and ScreenCaptureKit is the modern
  capture API.
- Capture inside the iOS app from VNC pixels: rejected because that cannot
  reduce VNC network payload or server update timing.

## D3 - Use VideoToolbox H.264 first

**Decision**: The first codec candidate is H.264 through VideoToolbox, with
hardware acceleration allowed and low-latency settings explored in the helper
prototype.

**Rationale**:
- Apple describes VideoToolbox as providing direct access to hardware encoders
  and decoders.
- Apple has specific low-latency H.264 guidance and encoder settings intended
  for real-time use.
- H.264 is the broadest first compatibility target across iPhone, iPad, and
  macOS. HEVC can be evaluated after the transport and benchmark gates exist.

**Sources**:
- Apple VideoToolbox: https://developer.apple.com/documentation/videotoolbox
- Apple low-latency VideoToolbox H.264 WWDC session: https://developer.apple.com/videos/play/wwdc2021/10158/
- Apple hardware encoder setting: https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_enablehardwareacceleratedvideoencoder

**Alternatives considered**:
- HEVC first: deferred for compatibility and complexity.
- Software x264 or FFmpeg embedded in the app/helper: rejected for the first
  milestone because platform hardware paths should be measured first.

## D4 - Keep VNC as control and fallback

**Decision**: Helper video is visual-only in the first milestone. VNC remains
the control, input, clipboard, reconnect, diagnostics, and fallback transport.

**Rationale**:
- It keeps the trust boundary small: helper video does not carry user input.
- Existing Compose, pointer, Direct mode, PiP, diagnostics, and reconnect logic
  remain usable without helper video.
- Fallback to VNC gives a recovery path for stream stalls, permission changes,
  and codec errors.

**Alternatives considered**:
- Full custom remote desktop protocol: rejected as too large and not needed to
  test whether video representation solves the current bottleneck.
- Helper video without VNC: rejected because the product still needs robust
  input and fallback behavior.

## D5 - Use fixed-catalog diagnostics and aggregate benchmark bands

**Decision**: Helper-video diagnostics and benchmark artifacts must report only
fixed labels and aggregate bands, never frame content, byte counters,
coordinates, display dimensions, endpoints, tokens, host names, or exact
per-frame timings.

**Rationale**:
- Screen frames are the highest-sensitivity data class in the product.
- Existing VNC performance work already uses safe labels, permille proxies, and
  aggregate timing bands. Helper video should follow the same reporting shape.
- Aggregate bands are sufficient to decide whether a candidate beats the VNC
  gate without turning artifacts into screen recordings or traffic logs.

**Sources**:
- `.specify/memory/constitution.md` principle IV
- `artifacts/benchmarks/2026-06-06-sustained-usability-candidate-contract.md`

**Alternatives considered**:
- Export sample frames for quality analysis: rejected for automation. Manual
  visual checks may record redacted notes, but frame artifacts are not
  committed by default.
- Raw byte counters: rejected by the existing benchmark privacy posture.

## D6 - Probe ScreenCaptureKit permission before shareable content

**Decision**: The first helper capture probe checks Screen Recording permission
with `CGPreflightScreenCaptureAccess()` before querying ScreenCaptureKit
shareable content.

**Rationale**:
- Apple documents ScreenCaptureKit as the high-performance screen/audio capture
  framework and shows `SCShareableContent` as the source of displays, apps, and
  windows that can be captured.
- Apple's sample notes that first run prompts for Screen Recording permission
  and that the app needs a restart after granting permission.
- A preflight check lets the helper report `permissionMissing` without touching
  shareable content, avoiding accidental prompts or unsafe content metadata in
  diagnostics.

**Sources**:
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple Capturing screen content in macOS: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- Apple `CGRequestScreenCaptureAccess`: https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess%28%29

**Alternatives considered**:
- Query `SCShareableContent` first and infer permission from errors: rejected
  because errors are not diagnostic-safe and the permission boundary should be
  explicit.
- Request permission automatically from the CLI smoke: rejected for this PR;
  the helper should expose fixed state first, then a later UI/pairing flow can
  decide when to request permission.

## D7 - Gate the first VideoToolbox H.264 prototype

**Decision**: The first helper encoder prototype creates and prepares a
VideoToolbox H.264 compression session only when
`NARU_HELPER_VIDEO_ENCODER_PROTOTYPE` is explicitly enabled.

**Rationale**:
- Apple documents `VTCompressionSessionCreate` as the API for creating a video
  compression session; the session outputs compressed frames through callback
  or output-handler paths.
- Apple's realtime compression property recommends timely compression for
  realtime clients, which matches remote-control visual latency goals.
- Apple's low-latency rate-control encoder specification selects a low-latency
  H.264 path that avoids frame reordering/lookahead behavior, fitting the
  interactive remote desktop target.
- Keeping this behind a helper flag lets the repo verify codec availability
  without changing VNC visual defaults, exposing binary payloads, or requiring
  a paired helper transport.

**Sources**:
- Apple `VTCompressionSessionCreate`: https://developer.apple.com/documentation/videotoolbox/vtcompressionsessioncreate%28allocator%3Awidth%3Aheight%3Acodectype%3Aencoderspecification%3Aimagebufferattributes%3Acompresseddataallocator%3Aoutputcallback%3Arefcon%3Acompressionsessionout%3A%29
- Apple `kVTCompressionPropertyKey_RealTime`: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_realtime
- Apple `kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder`: https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_enablehardwareacceleratedvideoencoder
- Apple `kVTVideoEncoderSpecification_EnableLowLatencyRateControl`: https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_enablelowlatencyratecontrol
- Apple Encoding video for low-latency conferencing: https://developer.apple.com/documentation/videotoolbox/encoding-video-for-low-latency-conferencing

**Alternatives considered**:
- Enable VideoToolbox probing by default: rejected because this is still a
  prototype and should not change helper startup behavior.
- Encode a real captured frame in the first encoder PR: rejected because the
  transport, payload handling, and privacy review need to land separately.
- Report dimensions, output size, or exact timing from the probe: rejected by
  the helper-video diagnostic privacy boundary.

## D8 - Authenticate helper-video request envelopes with HMAC

**Decision**: Helper-video app-to-helper request envelopes carry an
`hmac-sha256` `authProof` over schema version, request ID, message type, and
profile fingerprint using the pairing secret as local key material. Helper
responses omit `authProof`.

**Rationale**:
- The transport is private-network scoped, but private networks still need
  per-profile request authentication before any screen-stream capability or
  stream-start operation.
- Apple CryptoKit documents HMAC as a message authentication code based on a
  shared symmetric key and notes that HMAC authenticates data but does not hide
  it. That matches this slice: request integrity/authentication first, no claim
  of payload encryption.
- Signing the message type and profile fingerprint prevents replaying a proof
  across helper-video message kinds or saved profiles.
- Omitting `authProof` from helper responses keeps diagnostics and logs from
  accidentally treating proofs as safe catalog data.

**Sources**:
- Apple CryptoKit: https://developer.apple.com/documentation/cryptokit
- Apple HMAC: https://developer.apple.com/documentation/cryptokit/hmac
- Apple SymmetricKey: https://developer.apple.com/documentation/cryptokit/symmetrickey

**Alternatives considered**:
- Send the raw pairing secret in each helper-video envelope: rejected because
  the wire contract should not serialize reusable secrets.
- Leave helper video authenticated only by network locality: rejected because
  helper video crosses a stronger screen-capture privacy boundary.
- Add encryption in this transport PR: deferred; the current task is request
  authentication and typed framing, while encrypted transport policy needs a
  separate compatibility/security review.

## D9 - Build iOS display prototype around CoreMedia sample buffers

**Decision**: The first iOS helper-video decode/display prototype converts
Annex-B H.264 access-unit payloads into AVCC `CMSampleBuffer` values and feeds
them to `AVSampleBufferDisplayLayer`.

**Rationale**:
- Apple documents `AVSampleBufferDisplayLayer` as the platform layer for
  displaying compressed or uncompressed sample buffers.
- CoreMedia exposes `CMVideoFormatDescriptionCreateFromH264ParameterSets`,
  which lets the app cache SPS/PPS parameter sets from helper access units
  without logging payload bytes.
- CoreMedia's `CMSampleBufferCreateReady` creates ready sample buffers from a
  `CMBlockBuffer`, format description, timing, and sample-size entry. This
  gives the app a thin platform handoff while keeping decoded frames out of
  diagnostics and benchmark artifacts.

**Sources**:
- Apple `AVSampleBufferDisplayLayer`: https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer
- Apple `CMVideoFormatDescriptionCreateFromH264ParameterSets`: https://developer.apple.com/documentation/coremedia/cmvideoformatdescriptioncreatefromh264parametersets%28allocator%3Aparametersetcount%3Aparametersetpointers%3Aparametersetsizes%3Analunitheaderlength%3Aformatdescriptionout%3A%29
- Apple `CMSampleBufferCreateReady`: https://developer.apple.com/documentation/coremedia/cmsamplebuffercreateready%28allocator%3Adatabuffer%3Aformatdescription%3Asamplecount%3Asampletimingentrycount%3Asampletimingarray%3Asamplesizeentrycount%3Asamplesizearray%3Asamplebufferout%3A%29

**Alternatives considered**:
- Decode helper video into raw pixel buffers before display: deferred because
  the first path should measure platform display/decode behavior before adding
  app-side pixel copies.
- Persist access-unit payloads for visual QA: rejected because encoded screen
  content is not diagnostic-safe.
- Require live helper transport before adding app decode code: rejected because
  a fake access-unit test harness can lock payload framing and failure behavior
  before any live stream sends screen content.

## D10 - Add a real VideoToolbox synthetic access-unit source before live capture

**Decision**: Before wiring ScreenCaptureKit frames into the helper sender, add
a synthetic `CVPixelBuffer` source that uses VideoToolbox to emit real H.264
compressed samples, converts those samples into Annex-B helper
`videoAccessUnit` payloads, and drives the existing helper TCP harness and iOS
sample-buffer factory.

**Rationale**:
- Apple documents the VideoToolbox compression workflow as creating and
  configuring a compression session, encoding frames with
  `VTCompressionSessionEncodeFrame`, receiving compressed output through the
  compression callback, completing pending frames with
  `VTCompressionSessionCompleteFrames`, and invalidating the session.
- The helper wire contract already expects Annex-B payloads. VideoToolbox
  compressed sample data is copied out of `CMBlockBuffer` and converted into
  start-code-framed NAL units while SPS/PPS are emitted as a separate
  `parameterSet` access unit.
- This removes fake H.264 byte sentinels from the benchmark helper-video path
  without starting a real screen capture stream or exporting frames, display
  dimensions, endpoints, byte counts, exact timings, or payload data.

**Sources**:
- Apple `VTCompressionSession`: https://developer.apple.com/documentation/videotoolbox/vtcompressionsession-api-collection
- Apple `VTCompressionSessionEncodeFrame`: https://developer.apple.com/documentation/videotoolbox/vtcompressionsessionencodeframe
- Apple `VTCompressionSessionCompleteFrames`: https://developer.apple.com/documentation/videotoolbox/1428303-vtcompressionsessioncompletefram
- Apple `CMBlockBufferCopyDataBytes`: https://developer.apple.com/documentation/coremedia/cmblockbuffercopydatabytes

**Alternatives considered**:
- Keep using fixed fake access-unit bytes in the benchmark TCP probe: rejected
  because it does not exercise encoder output shape, parameter-set extraction,
  or AVCC-to-Annex-B conversion.
- Wire ScreenCaptureKit directly into the next PR: deferred because capture
  permissions, display selection, frame cadence, and privacy review should be
  isolated from the encoder payload-format gate.

## D11 - Feed finite ScreenCaptureKit frames through the same VideoToolbox encoder

**Decision**: Add a finite ScreenCaptureKit access-unit source that captures a
small batch of display frames, extracts only in-memory `CVPixelBuffer` images,
feeds them through the shared VideoToolbox H.264 encoder, and exposes a
`screen-capturekit-tcp` benchmark probe mode through the existing authenticated
local TCP harness.

**Rationale**:
- Apple documents ScreenCaptureKit as the high-performance API for screen
  capture and describes `SCStreamOutput` as the delegate path that receives
  `CMSampleBuffer` frames from an `SCStream`.
- The first live-capture slice should stay finite and explicit: it checks
  Screen Recording permission before starting capture, selects an available
  display, keeps `queueDepth` at three, throttles capture with
  `minimumFrameInterval`, includes the visible cursor, and stops after the
  requested batch.
- The benchmark report still emits only fixed helper-video state labels and
  aggregate health bands. It must not export frame content, dimensions, bytes,
  endpoints, host names, OS error text, payloads, or exact timings.

**Sources**:
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple `SCStreamOutput`: https://developer.apple.com/documentation/screencapturekit/scstreamoutput
- Apple `SCStream.addStreamOutput`: https://developer.apple.com/documentation/screencapturekit/scstream/addstreamoutput%28_%3Atype%3Asamplehandlerqueue%3A%29
- Apple `SCStreamConfiguration.queueDepth`: https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
- Apple `SCStreamConfiguration.minimumFrameInterval`: https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval
- Apple `SCFrameStatus`: https://developer.apple.com/documentation/screencapturekit/scframestatus

**Alternatives considered**:
- Start the long-lived helper sender in the same PR: rejected because permission
  prompts, lifecycle restart behavior, display reselection, and iOS sustained
  decode backpressure need their own focused review.
- Export a captured frame or encoded byte sample for QA: rejected because that
  violates the helper-video diagnostic privacy boundary.

## D12 - Expose helper-video listen as an explicit finite helper entrypoint

**Decision**: Add `NaruHelper --video-listen` as an explicit, opt-in CLI
entrypoint that starts the authenticated helper-video TCP server with required
pairing token and profile fingerprint inputs, a default private-network
helper-video port, and an explicit finite source choice:
`screen-capturekit` or `synthetic-encoded`.

**Rationale**:
- The app-side session runner and benchmark probes need a real helper process
  entrypoint before a true live helper-video access-unit benchmark can replace
  in-process synthetic TCP setup.
- Keeping source choice explicit prevents a synthetic benchmark source from
  being mistaken for a live desktop capture and makes ScreenCaptureKit
  permission failures easier to isolate.
- Supporting `--token-env` and `--profile-fingerprint-env` gives local and
  future packaged launch flows an argv-safe path while preserving direct
  arguments for deterministic tests and short local smoke runs.
- The first CLI entrypoint remains finite per `startStream` request so startup,
  authentication, payload framing, permission state, and safe failure behavior
  can be reviewed before adding long-lived adaptive cadence, backpressure, and
  keyframe recovery.
- Pairing secrets and profile fingerprints are command inputs only. Reports
  and diagnostics continue to emit fixed labels and coarse helper-video state,
  not endpoints, payloads, byte counts, dimensions, exact timings, host names,
  or raw OS errors.

**Alternatives considered**:
- Start helper video from the existing `--listen` text-helper mode: rejected
  because video crosses a separate Screen Recording permission boundary and
  should be independently observable and revocable.
- Make `screen-capturekit` implicit default for every smoke run: rejected
  because many development contexts lack Screen Recording permission and need a
  deterministic VideoToolbox-only loopback source.
- Jump straight to a long-lived adaptive sender: deferred until the finite
  process entrypoint, app runner, and benchmark report path are all connected
  and reviewed.

## D13 - Benchmark the external helper-listen path before live capture default

**Decision**: Add an `external-helper-synthetic-encoded-tcp` benchmark probe
mode that launches `NaruHelper --video-listen` as a separate process with
env-indirected synthetic pairing state, connects through the same
`HelperVideoStreamNetworkClient`, and reports only aggregate helper-video health
bands.

**Rationale**:
- The in-process TCP harness proves frame parsing and authentication, but it
  bypasses the real helper executable, CLI parsing, process environment,
  listener lifecycle, and app-to-helper connection timing.
- Apple documents `Foundation.Process` as a process launched with an executable
  URL, arguments, standard streams, and environment. That is the closest local
  benchmark shape before the packaged helper/pairing lifecycle exists.
- The first external-helper benchmark should use the deterministic
  `synthetic-encoded` source so a missing Screen Recording permission does not
  hide process/listener regressions.
- The helper path, environment variable names or values, endpoint, pairing
  secret, profile fingerprint, access-unit payloads, byte counts, dimensions,
  raw errors, and exact timings remain outside the report.

**Sources**:
- Apple `Process`: https://developer.apple.com/documentation/foundation/process
- Apple `Process.executableURL`:
  https://developer.apple.com/documentation/foundation/process/executableurl

**Alternatives considered**:
- Call the helper listen runtime directly from the benchmark: rejected because
  that would keep the benchmark in the same process and miss CLI/process
  lifecycle regressions.
- Use `screen-capturekit` for the first external-helper benchmark: deferred
  because permission-missing states need to stay distinguishable from helper
  launch and listener failures.
- Export the helper executable path or port on failure: rejected because the
  benchmark report privacy boundary allows only fixed labels and aggregate
  health bands.

## D14 - Add external helper ScreenCaptureKit benchmark as the live-capture gate

**Decision**: Add an `external-helper-screen-capturekit-tcp` benchmark probe
mode that launches the real `NaruHelper --video-listen` process with
`--video-source screen-capturekit`, then connects through the helper-video
network client and reports only fixed helper-video health labels.

**Rationale**:
- The external synthetic probe validates process launch, CLI parsing, listener
  readiness, authenticated start, and finite H.264 access-unit delivery. The
  next gate should keep the same external process boundary but swap the source
  to finite ScreenCaptureKit capture.
- Preflighting Screen Recording permission before launch keeps missing
  permission runs from touching shareable content and preserves the fixed
  `helper-video-permission-missing` report path.
- Mapping a rejected helper `startStream` response through fixed issue codes
  prevents the benchmark from accidentally treating permission or codec
  rejection as a healthy stream.
- Reports still omit helper executable paths, environment variable names or
  values, endpoints, frame payloads, byte counts, dimensions, raw errors, and
  exact timings.

**Sources**:
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple `CGPreflightScreenCaptureAccess`:
  https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29
- Apple `Process`: https://developer.apple.com/documentation/foundation/process

**Alternatives considered**:
- Use only the in-process `screen-capturekit-tcp` probe: rejected because it
  bypasses helper executable launch and listener lifecycle.
- Launch the helper even when preflight permission is missing: rejected because
  the benchmark should not prompt, inspect shareable content, or blur
  permission failures with process/listener regressions.
- Promote ScreenCaptureKit helper video as a default transport after this
  probe: deferred until physical-device sustained decode, thermal, and fallback
  evidence exists.

## D15 - Keep Screen Recording permission request explicit

**Decision**: Add `NaruHelper --video-request-screen-recording-permission` as
the only helper-video CLI path that calls `CGRequestScreenCaptureAccess()`.
Capability checks and benchmark probes continue to use preflight-only behavior.

**Rationale**:
- Apple's CoreGraphics screen-capture APIs separate checking existing Screen
  Recording access from requesting it. Naru should preserve that distinction so
  benchmark runs do not unexpectedly show permission UI.
- A dedicated helper CLI gives live-benchmark setup a repeatable way to make
  the permission gate actionable before running
  `external-helper-screen-capturekit-tcp`.
- `VNCLiveBenchmark --environment-preflight` should surface the same gate as
  fixed schema labels when a ScreenCaptureKit helper-video probe is selected,
  so setup failures route to a next action before the benchmark attempts
  capture.
- The response uses only fixed catalog labels and does not query
  `SCShareableContent`, so missing or denied permission remains distinguishable
  from capture-source and listener failures.

**Sources**:
- Apple `CGRequestScreenCaptureAccess`:
  https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess%28%29
- Apple `CGPreflightScreenCaptureAccess`:
  https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29

**Alternatives considered**:
- Request permission inside `--video-capability`: rejected because capability
  should be a quiet diagnostic preflight.
- Request permission automatically from live benchmark modes: rejected because
  benchmark reports should stay deterministic and should not mix user prompts
  with transport performance gates.

## D16 - Delegate external-helper ScreenCaptureKit permission checks to the helper process

**Decision**: `external-helper-screen-capturekit-tcp` should not be blocked by
the benchmark process's `CGPreflightScreenCaptureAccess()` result. The
environment preflight reports `delegatedToHelper`, launches remain explicit,
and the external helper process reports `permissionMissing` from its own
`startStream` path when needed.

**Rationale**:
- The benchmark process and helper process may have different macOS TCC
  identities, especially once the helper is packaged or launched from a stable
  bundle path.
- Blocking external-helper capture on the benchmark process permission would
  keep live helper-video benchmarking broken even after the helper process has
  Screen Recording permission.
- The helper runtime already preflights Screen Recording before touching
  `SCShareableContent`, so delegating the check preserves the privacy boundary
  while testing the real process that will capture frames.

**Sources**:
- Apple `CGPreflightScreenCaptureAccess`:
  https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29
- Apple ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit

**Alternatives considered**:
- Keep benchmark-process preflight for external-helper mode: rejected because
  it can false-block a correctly permissioned helper process.
- Request Screen Recording permission from `VNCLiveBenchmark`: rejected because
  benchmark runs should not show permission UI and should not request capture
  permission for the wrong process identity.
