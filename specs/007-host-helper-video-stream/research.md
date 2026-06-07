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

## D17 - Report helper Screen Recording permission identity as fixed labels

**Decision**: `NaruHelper --video-capability` and
`--video-request-screen-recording-permission` report schema `2`
`permissionIdentity` labels that classify the current helper process as an app
bundle, command-line tool, SwiftPM build artifact, unsupported platform, or
unknown context. The paired `grantHint` remains a fixed action label such as
`grantAppBundle`, `grantCurrentHelperExecutable`, or
`useStableHelperExecutable`.

**Rationale**:
- macOS Screen Recording permission is process-identity sensitive. Live
  benchmark setup needs to know whether it is granting a stable helper target
  or a development build artifact without leaking executable paths.
- `swift run` / `.build/debug/NaruHelper` is useful for fast iteration but is a
  poor long-lived permission target. The fixed `swiftPMBuildArtifact` plus
  `useStableHelperExecutable` labels make that actionable before repeated live
  benchmark runs.
- The response must stay safe for diagnostic artifacts, so it reports no bundle
  identifiers, usernames, parent process names, executable paths, or raw TCC
  details.

**Sources**:
- Apple `Bundle`: https://developer.apple.com/documentation/foundation/bundle
- Apple ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit
- Apple `CGRequestScreenCaptureAccess`:
  https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess%28%29

**Alternatives considered**:
- Emit the helper executable path or bundle identifier: rejected because live
  benchmark artifacts must not include local paths or user/device identifiers.
- Keep only `permissionMissing`: rejected because it does not explain whether
  the user should grant a stable helper app/binary or stop using a transient
  development artifact for live capture.

## D18 - Use a stable development helper app wrapper for live ScreenCaptureKit setup

**Decision**: Add `scripts/install-naru-helper-dev-app.sh` to build
`NaruHelper`, wrap it in a locally installed `NaruHelperDev.app`, sign that app
with exactly one local Apple Development identity when available, fall back to
ad-hoc signing otherwise, and optionally set `NARU_HELPER_EXECUTABLE` through
`launchctl` for future live benchmark shells.

**Rationale**:
- Screen Recording approval should be tied to the helper process that will
  actually capture frames. A SwiftPM build artifact is convenient but unstable
  as a repeated TCC permission target.
- A small dev app wrapper gives local benchmarking an app-bundle identity
  (`appBundle` / `grantAppBundle`) before the production helper packaging work
  is ready.
- Apple Developer Forums reports that Screen Recording permission can appear to
  reset across development builds when ad-hoc signing changes the app identity;
  using an Apple Development signing identity when it is unambiguous should make
  the development helper a more stable permission target.
- The wrapper is explicitly development-only. It does not change the product
  helper distribution, launchd lifecycle, revocation model, or user-facing
  install UX.

**Sources**:
- Apple `Bundle`: https://developer.apple.com/documentation/foundation/bundle
- Apple ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit
- Apple Code Signing Guide:
  https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/
- Apple Developer Forums - ScreenCaptureKit permissions lost after every build:
  https://developer.apple.com/forums/thread/819406

**Alternatives considered**:
- Continue granting `.build/debug/NaruHelper`: rejected because it keeps live
  benchmark permission state coupled to transient build output.
- Always use ad-hoc signing: rejected because it can make the development
  helper a less stable Screen Recording permission target across rebuilds.
- Always use the first Apple Development identity: rejected because multiple
  teams would be ambiguous and could sign with the wrong account. Use an
  explicit identity in that case.
- Jump directly to production helper packaging: deferred because the current
  blocker is live benchmark enablement, while the production helper still needs
  a broader install/update/revocation design.

## D19 - Preflight external helper capability before ScreenCaptureKit benchmark runs

**Decision**: `VNCLiveBenchmark --environment-preflight` schema `5` launches
the selected external helper with `--video-capability` when
`external-helper-screen-capturekit-tcp` is selected. It records only fixed
capability and permission identity labels, then blocks the live gate with a
specific setup action when helper permission or helper availability is not
ready.

**Rationale**:
- After D16, the benchmark process no longer false-blocks external helper
  ScreenCaptureKit runs. The next useful setup gate is the helper process's own
  quiet capability result.
- Running helper capability in preflight avoids spending a live benchmark run
  just to rediscover `helper-video-permission-missing`.
- Fixed setup actions can distinguish
  `grant-helper-video-app-screen-recording-permission` from
  `install-stable-helper-video-executable` without exposing helper paths, bundle
  identifiers, endpoints, or raw TCC details.

**Sources**:
- Apple `Process`: https://developer.apple.com/documentation/foundation/process
- Apple ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit
- Apple `CGPreflightScreenCaptureAccess`:
  https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29

**Alternatives considered**:
- Keep preflight as `delegatedToHelper` only: rejected because it forces the
  user to run a benchmark to learn that the helper app bundle still lacks
  Screen Recording permission.
- Emit helper executable paths in the preflight report: rejected by the safe
  benchmark artifact boundary.

## D20 - Bound external helper process waits in benchmark setup

**Decision**: `VNCLiveBenchmark --environment-preflight` schema `6` gives the
external helper `--video-capability` command a bounded wait and emits fixed
`timedOut` labels when it does not return. The actual external helper-video TCP
probe now uses the same bounded termination helper when cleaning up the helper
process after a smoke run.

**Rationale**:
- A diagnostic or benchmark preflight must not hang merely because the helper
  executable is wedged, waiting on an OS prompt, or blocked before writing JSON.
- The timeout path should be actionable without exposing helper paths, process
  arguments, stderr, bundle identifiers, or host configuration.
- Reusing the bounded cleanup for live helper probes reduces the risk that a
  failed helper server keeps `VNCLiveBenchmark` stuck after the client side has
  already produced a result.

**Sources**:
- Apple `Process`: https://developer.apple.com/documentation/foundation/process
- POSIX signal behavior through Darwin `kill(2)` for force cleanup on macOS.

**Alternatives considered**:
- Keep unbounded `waitUntilExit()`: rejected because it conflicts with the
  non-blocking diagnostic goal.
- Emit raw helper stderr on timeout: rejected by the safe benchmark artifact
  boundary.

## D21 - Add helper-video probe-only benchmark mode

**Decision**: Add `VNCLiveBenchmark --helper-video-probe-only` so helper-video
probe modes can be exercised without live VNC target credentials. The report
wraps the existing helper-video comparison schema, records the selected probe
mode, and emits only fixed helper-video labels, aggregate health bands,
verdicts, and fixed issue codes.

**Rationale**:
- Helper capture/encode/transport problems should be diagnosable before
  spending a full live VNC benchmark run.
- After granting macOS Screen Recording to the helper app bundle, this gives a
  fast first confirmation that external ScreenCaptureKit access units can travel
  through the helper-video path.
- The mode is also useful while permission is missing: synthetic external
  helper probes can stay green, while the ScreenCaptureKit probe reports only
  `helper-video-permission-missing`.

**Alternatives considered**:
- Keep helper-video smoke embedded only in full live reports: rejected because
  it requires host credentials and runs unrelated VNC probes when the user only
  needs helper setup evidence.
- Write raw helper diagnostic JSON to artifacts: rejected by the safe benchmark
  artifact boundary.

## D22 - Standardize launchctl-backed live benchmark entrypoints

**Decision**: Add `scripts/run-naru-live-benchmark.sh` as a local development
wrapper for repeated live benchmark runs. The wrapper imports
`NARU_HELPER_EXECUTABLE`, `NARU_LIVE_MAC_HOST`, `NARU_LIVE_MAC_PORT`,
`NARU_LIVE_MAC_PASSWORD`, and `NARU_LIVE_STIMULUS_COMMAND` from `launchctl`
when the current shell does not already provide them, then runs fixed
preflight, helper-video probe-only, helper capability, permission request, or
short constrained-cellular comparison modes.

**Rationale**:
- Codex, GUI-launched terminals, and manual shells do not always inherit the
  same process environment. `launchctl getenv` is the stable source for this
  development machine's live credential references.
- A wrapper prevents accidental command-line password literals while still
  making repeated helper-video and VNC fallback benchmarks easy to run.
- The wrapper delegates report generation to the existing safe CLIs, so it does
  not add a second JSON schema or print credential values, helper paths,
  endpoints, payloads, byte counts, dimensions, raw OS errors, or exact helper
  timings.

**Alternatives considered**:
- Add a `VNCLiveBenchmark --launchctl-env` flag immediately: deferred because
  the current need is a development workflow wrapper, and changing the CLI's
  environment provider would add a broader surface to test.
- Document only the long `NARU_LIVE_*="$(launchctl getenv ...)"` command
  prefixes: rejected because the repeated command shape is easy to mistype and
  obscures the actual benchmark mode being run.

## D23 - Add a fixed helper-video readiness sweep before the true capture gate

**Decision**: Add a launchctl-backed `helper-readiness-sweep` mode that runs
helper capability, environment preflight, external synthetic helper-video, and
external ScreenCaptureKit helper-video probes as one JSON object. The sweep
rejects caller-supplied extra arguments and converts subcommand failures into
step-specific fixed failure labels without printing raw helper stderr.

**Rationale**:
- T031 needs a true ScreenCaptureKit access-unit live benchmark, but the
  current helper app bundle still reports missing Screen Recording permission
  and explicit permission request returns `notGranted`.
- Apple documents ScreenCaptureKit as the screen-capture framework and notes
  that macOS prompts for Screen Recording permission and requires restarting
  the app after granting permission. A readiness sweep should therefore
  distinguish "permission setup still blocked" from "helper transport broken".
- The external synthetic H.264 path still proves the helper-video network and
  iOS sample-buffer route without live screen pixels. Keeping it in the same
  sweep reduces false diagnosis when only ScreenCaptureKit permission is
  missing.
- Step-specific fallback labels preserve enough trend information for repeated
  readiness runs while still avoiding raw stderr, helper paths, endpoints, and
  OS error details.

**Sources**:
- Apple ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit
- Apple Capturing screen content in macOS:
  https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- Apple VideoToolbox:
  https://developer.apple.com/documentation/videotoolbox
- Apple low-latency H.264 VideoToolbox session:
  https://developer.apple.com/videos/play/wwdc2021/10158/

**Alternatives considered**:
- Automatically request Screen Recording inside the sweep: rejected because
  readiness checks should be deterministic and should not mix benchmark output
  with OS permission UI.
- Continue running four separate commands manually: rejected because it is too
  easy to skip the synthetic control path or lose the exact setup-action label.
- Emit raw helper stderr when a step fails: rejected by the helper-video
  privacy boundary.

## D24 - Add an explicit Screen Recording setup command

**Decision**: Add a launchctl-backed `screen-recording-setup` mode that checks
the selected helper's safe capability labels, runs the helper's explicit Screen
Recording permission request, opens the macOS Screen Recording settings pane,
and checks capability again. The mode emits one safe JSON object with fixed
status labels and supports `NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip`
for non-interactive verification.

**Rationale**:
- The helper app bundle currently reports `permissionMissing`, and the
  explicit permission request returns `notGranted`. The next useful action is
  not another VNC comparison; it is getting the stable helper app bundle
  visible in macOS Screen Recording settings and then rerunning readiness.
- Apple documents ScreenCaptureKit as permission-gated screen capture and notes
  that capture becomes available after the user grants Screen Recording and
  restarts the app. The setup command should therefore open the user-visible
  settings boundary rather than attempting to grant TCC permission itself.
- Keeping the command inside the launchctl runner avoids printing helper paths
  or credential values and keeps all setup evidence in fixed labels.

**Sources**:
- Apple ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit
- Apple Capturing screen content in macOS:
  https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos

**Alternatives considered**:
- Programmatically modify macOS TCC state: rejected because Screen Recording is
  a user-controlled privacy boundary and should not be bypassed by benchmark
  tooling.
- Leave setup as separate manual commands: rejected because the repeated helper
  path needs one safe command that records before/request/after labels without
  exposing local paths or raw OS errors.
- Always open System Settings during automated checks: rejected because CI and
  non-interactive validation need a no-UI path that still verifies JSON shape.

## D25 - Benchmark the app-side helper-video runner path before true capture

**Decision**: Add an opt-in `HelperVideoAppRunnerBenchmarkTests` target path
that measures finite helper-video H.264 access units through app visual
transport selection and CoreMedia sample-buffer creation. The normal test loop
skips the benchmark unless `NARU_RUN_SIM_BENCHMARKS=1` is set. macOS SwiftPM
runs also attempt an optional VideoToolbox synthetic helper source and skip it
with a fixed label when the host encoder cannot provide access units.

**Rationale**:
- True ScreenCaptureKit helper-video evidence remains blocked until the stable
  helper app bundle receives macOS Screen Recording permission. The app can
  still reduce risk by benchmarking the post-network visual path that will run
  after helper access units arrive.
- The app-side runner is the boundary where accepted helper-video streams select
  visual transport, feed the renderer, mark health, or fall back to VNC. Making
  that path measurable prevents future smoothness work from focusing only on
  server/network probes.
- Keeping the benchmark opt-in preserves CI determinism and avoids exporting
  payload bytes, display dimensions, byte counts, helper endpoints, host names,
  credentials, exact timings, raw encoder errors, or frame content to artifacts.

**Alternatives considered**:
- Wait for Screen Recording permission before adding any helper-video benchmark:
  rejected because it leaves the app decode/display bridge unmeasured while a
  user-controlled macOS privacy setting is pending.
- Benchmark only the H.264 sample-buffer factory: rejected because it would miss
  visual transport selection, helper health updates, and VNC fallback state.
- Make the benchmark always run in CI: rejected because CPU, memory, and encoder
  characteristics vary by simulator/host and should be opt-in investigation
  evidence until physical-device gates exist.

## D26 - Bootstrap helper-video only after VNC is already usable

**Decision**: Start the app-side helper-video stream only after the selected VNC
profile has produced its first framebuffer and the VNC input/control clients are
active. The bootstrap loads the helper-video pairing secret off the MainActor,
then returns to the app model to run the helper-video session runner. Helper
start failures keep the VNC framebuffer, Compose draft, and pointer input path
active while marking only fixed helper-video failure labels.

**Rationale**:
- Helper video is visual-only for the first milestone; VNC remains the control
  and fallback transport. Starting helper video after the first VNC frame makes
  that invariant concrete in the app lifecycle.
- Loading the helper pairing secret outside MainActor avoids turning Keychain or
  credential-store latency into viewer chrome freezes.
- The session runner already owns safe visual selection, renderer handoff,
  health updates, and VNC fallback. A connect bootstrap seam lets tests inject a
  fake helper stream today and lets the production default use the authenticated
  helper-video network client when the profile is enabled.

**Alternatives considered**:
- Start helper video before VNC connects: rejected because helper setup failure
  could delay or confuse the baseline VNC view/control path.
- Require a separate manual helper-video toggle after every connect: rejected for
  paired private-network profiles because it would make benchmark and physical
  validation less representative of the intended opt-in profile behavior.
- Store raw helper start errors or pairing-secret details for debugging:
  rejected by the helper-video privacy boundary; fixed failure codes and
  aggregate health labels are sufficient for this layer.

## D27 - Add a network-backed app bootstrap smoke before physical live video

**Decision**: Add an opt-in macOS SwiftPM smoke benchmark that drives the
app-model helper-video bootstrap through a real authenticated loopback TCP
helper-video server/client path after the fake VNC connector supplies the first
framebuffer. The test still skips by default unless `NARU_RUN_SIM_BENCHMARKS=1`
is set.

**Rationale**:
- T029X proved the app lifecycle with an injected start-stream closure, while
  T029B/T029D proved the helper-video network and H.264 access-unit pieces in
  isolation. The next useful automatic gate is their composition at the app
  bootstrap boundary.
- The true live ScreenCaptureKit benchmark still depends on the helper app
  bundle's macOS Screen Recording permission. A loopback TCP smoke avoids that
  privacy setting while validating the wire protocol, H.264 sample-buffer path,
  VNC first-frame ordering, and VNC pointer/control retention together.
- Keeping it opt-in avoids adding host encoder/network variance to normal CI and
  keeps committed evidence to fixed pass/skip labels instead of raw timings,
  payload bytes, dimensions, endpoints, byte counts, host names, credentials, or
  raw OS errors.

**Alternatives considered**:
- Put the real TCP path only in `NaruRemoteAppTests`: rejected because this is
  benchmark-style, host-dependent evidence and belongs with the existing opt-in
  helper-video app-runner benchmark.
- Wait for physical iPhone live ScreenCaptureKit before composing these pieces:
  rejected because it would leave the app/network seam untested while a manual
  macOS privacy permission is pending.
- Record measured TCP startup timings in the committed artifact: rejected by
  the helper-video privacy posture; local XCTest output is enough for
  investigation and committed docs should stay catalog-level.

## D28 - Preflight physical iPhone signing before live helper-video gates

**Decision**: Extend the launchctl-backed benchmark runner with a
`physical-device-preflight` mode that discovers whether a physical iPhone is
selectable and classifies Xcode build/signing blockers with fixed labels. The
mode filters discovery to iPhone devices instead of accepting any physical iOS
device, and it may run a physical-device `xcodebuild` build check while
capturing and classifying the output instead of printing raw logs.

**Rationale**:
- The connected iPhone is now visible to Xcode, but the physical helper-video
  gates still cannot run if signing/provisioning fails before the app launches.
  A safe preflight separates "no device", "ambiguous device", "development team
  missing", "Xcode account missing", and "development provisioning profile
  missing" before a long T030/T031 attempt.
- Physical-device readiness is a privacy-sensitive diagnostic surface: device
  names, device IDs, provisioning profile names, bundle identifiers, raw
  xcodebuild logs, live VNC credentials, helper paths, and exact timings are not
  needed to decide the next setup action.
- Keeping this in the local runner matches the existing live helper-video setup
  flow and avoids committing a personal development team ID to `project.yml`.
- The runner may infer a development team only when the local keychain exposes
  exactly one Apple Development team. The inferred Team ID is passed only to the
  captured `xcodebuild` child process; the report emits the fixed
  `developmentTeamStatus=inferred` label and never prints the Team ID.

**Alternatives considered**:
- Commit `DEVELOPMENT_TEAM` to the XcodeGen project: rejected because this repo
  should not encode a developer's personal signing team.
- Paste raw `xcodebuild` failures into artifacts: rejected because they can
  expose device identity, account/profile names, local paths, and bundle IDs.
- Wait until a physical test fails and inspect the console manually: rejected
  because T030/T031 should fail fast with actionable fixed setup labels.
- Always infer from the first Apple Development certificate: rejected because
  multiple teams would make the gate ambiguous and could build against the
  wrong account.

## D29 - Combine the VNC 10fps gate with helper-video readiness

**Decision**: Add `scripts/run-naru-live-benchmark.sh
remote-desktop-10fps-readiness`, a fixed launchctl-backed dashboard that
combines helper capability/preflight, external synthetic H.264 helper-video,
external ScreenCaptureKit helper-video, and the current VNC
`iphone-remote-desktop-10fps-v1` probe in one privacy-safe JSON object.

**Rationale**:
- The user's product floor is now explicit: a sustained visual path below
  `10fps` is a failure, not a warning. The current VNC path remains useful for
  input/control/fallback, but its latest live result is still around `1.89`
  content FPS with `receivePath` as the primary constraint.
- Helper-video synthetic H.264 already passes the safe probe, so the next
  promotion blocker is not the helper transport shape; it is true
  ScreenCaptureKit capture permission and physical iPhone evidence.
- A combined dashboard prevents repeated small VNC profile-only loops from
  obscuring the bigger product decision: if VNC is below 10fps and helper
  synthetic is healthy, the next large unit should unlock true helper-video
  capture/decode and physical-device verification.

**Alternatives considered**:
- Keep separate `glance-025-10fps-duration-probe` and `helper-readiness-sweep`
  commands only: rejected because it makes the product-level go/no-go harder to
  read from one artifact.
- Automatically promote helper-video after synthetic pass: rejected because
  ScreenCaptureKit permission, true live capture, fallback behavior, and
  physical iPhone thermal/gesture evidence are still required.
- Remove VNC from the dashboard: rejected because VNC remains the required
  control/input/fallback path and its 10fps failure is the reason helper-video
  is being advanced.

## D30 - Keep frame/video processing off the UI executor after physical freeze

**Decision**: Treat physical-device gesture/input freeze on first real VNC
connection as a MainActor isolation failure until proven otherwise. The VNC
frame-stream task now uses a detached worker for session connect,
`RFBFramePump.nextFrame`, decode waits, and pacing sleeps, hopping to
`NaruRemoteAppModel` only for current-session checks, publication, diagnostics,
and stats. Foreground VNC frames no longer feed the PiP sample-buffer layer, and
preview thumbnail sampling is performed in a utility detached task. The
helper-video runner is also non-MainActor, with only renderer enqueue/flush
isolated through an explicit main-actor renderer box.

**Rationale**:
- The observed physical iPhone failure mode was not merely low FPS: once a real
  connection started, gestures and keyboard input stopped responding. That
  points to blocking local work on the UI executor, especially full-frame
  sample-buffer conversion, synchronous thumbnail sampling, or a frame loop that
  inherited MainActor.
- The foreground viewer already has a Metal framebuffer path. Converting every
  received VNC framebuffer into `CMSampleBuffer` for PiP while PiP is not active
  duplicates local frame work and competes directly with pinch, pan, trackpad,
  and Compose input.
- A detached frame worker preserves the existing app-model state boundary while
  making the expensive/blocked side of the loop unable to monopolize SwiftUI's
  executor. Helper-video keeps its AVSampleBufferDisplayLayer calls on
  MainActor, but network start and session-result control flow no longer inherit
  the app chrome executor.

**Alternatives considered**:
- Only lower the VNC FPS/pacing cap: rejected because the failure is input
  freeze, not just excessive visual cadence.
- Keep feeding PiP layer host for every foreground frame so PiP can attach
  instantly: rejected because PiP is watch-only and explicitly user-started; a
  one-frame PiP preparation cost is preferable to freezing normal control.
- Move all SwiftUI-published state off MainActor: rejected because
  `ObservableObject` publication and AVSampleBufferDisplayLayer lifecycle still
  require main-actor boundaries. The safer split is worker-side network/decode
  with short main-actor publication hops.

## D31 - Isolate live frame publication from app chrome and input state

**Decision**: Move live framebuffer, dirty-rectangle, changed-pixel, and server
cursor publication into a dedicated `SessionFrameStore` observed only by the
viewport bridge. Keep the app model's snapshot values for tests, diagnostics,
pointer mapping, and PiP eligibility, but remove frame pixels and
`SessionStreamStats` from the app model's `@Published` surface. After the first
frame activates the session, subsequent content frames update the viewport
store without invalidating the whole shell, connection grid, compose dock, or
direct-keyboard subtree.

**Rationale**:
- The physical iPhone freeze still looked like a UI invalidation problem after
  the frame loop moved off MainActor: real frames could cause the entire
  `NaruRemoteAppModel` `ObservableObject` to publish, forcing SwiftUI to
  recompute app chrome and input controls at frame cadence.
- `RFBRawFramebuffer` is large and only the Metal viewport needs it. Keeping it
  in the app model snapshot for non-UI logic is acceptable, but using it as a
  top-level published property ties video cadence to text input, gestures, and
  navigation.
- Session lifecycle should publish on first frame and reconnect recovery, not
  on every later frame. Per-frame stats remain memory-only and diagnostics-safe;
  the connection-quality chip still publishes only when its coarse bucket
  changes.

**Verification**:
- `NaruRemoteAppModelTests/testStreamingFramesFlowThroughFrameEventsWithoutInvalidatingSwiftUIChrome`
  proves a second streaming content frame flows through `SessionFrameStore`
  while leaving `NaruRemoteAppModel.objectWillChange` unchanged.
- `swift test --filter NaruRemoteAppModelTests` passed after the split.

**Alternatives considered**:
- Leave `latestFramebuffer` as `@Published` and rely on lower FPS: rejected
  because even a low-FPS live stream can collide with keyboard and gesture
  responsiveness on iPhone.
- Move all app model state into the frame store: rejected because session
  lifecycle, input state, diagnostics, and profile UI should not observe the
  video cadence.
- Remove snapshot framebuffer values entirely: rejected because existing tests,
  pointer mapping, PiP start checks, and diagnostics use the latest frame as
  memory-only model state.

## D32 - Deliver steady VNC frames to Metal without SwiftUI frame-diff cadence

**Decision**: Split `SessionFrameStore` into a presentation revision and a
frame-event side channel. The SwiftUI viewport bridge observes only
presentation changes (first frame, framebuffer dimension changes, and clear),
while `MetalFramebufferView.Coordinator` subscribes to `framePublisher` and
enqueues same-size content frames directly into the Metal host. The first frame
still seeds the representable from SwiftUI so layout, aspect ratio, and
fallback views have a concrete framebuffer.

**Rationale**:
- PR #349 narrowed per-frame invalidation to the viewport subtree, but
  `@Published state` still made SwiftUI rebuild the representable at frame
  cadence. On physical iPhone that can still compete with UIKit gestures,
  keyboard composition, and renderer upload callbacks as soon as a real stream
  starts.
- The UIKit/Metal host already owns the hot pinch, pan, trackpad, cursor, and
  redraw path. Sending steady frames directly to that host keeps video cadence
  out of SwiftUI while preserving the existing texture upload gate and
  gesture-time redraw throttle.
- Framebuffer dimension changes must still publish through SwiftUI because
  they affect layout, aspect ratio, viewport transforms, and fallback preview
  composition. Same-size content changes do not.

**Verification**:
- `SessionFrameStoreTests/testSameSizeFramesEmitEventsWithoutSwiftUIPresentationRefresh`
  proves same-size frames emit frame events without bumping presentation state,
  while size changes still refresh presentation.
- `NaruRemoteAppModelTests/testStreamingFramesFlowThroughFrameEventsWithoutInvalidatingSwiftUIChrome`
  proves the second streamed frame updates the model/store and emits a frame
  event without invalidating app model or frame-store SwiftUI observation.

**Alternatives considered**:
- Keep `SessionFrameStore.state` as `@Published`: rejected because that still
  routes every frame through SwiftUI's update cycle.
- Replace the whole viewport with a fully imperative controller now: deferred
  because the current host already has the required imperative gesture and
  redraw hooks; the side channel removes the frame-diff bottleneck with less
  risk to input behavior.
- Publish only a sampled FPS through SwiftUI: rejected because the Metal
  renderer still needs every admitted frame event, even when the UI shell does
  not.

## D33 - Measure outbound input queue and write latency separately from frame cadence

**Decision**: Add privacy-safe outbound input responsiveness counters to the
session stream performance report. Key and pointer commands now record one
aggregate sample per accepted outbound queue operation: queue delay bucket,
operation timing bucket, and timeout count. The report does not include
coordinates, keysyms, text, endpoint data, byte counts, or exact timings.

**Rationale**:
- The post-frame-isolation physical iPhone symptom still needs sharper
  evidence: if gestures or keys feel frozen after connection, we must know
  whether touch/UI sampling is blocked, outbound input is queued behind an
  older write, or the RFB socket write itself is hanging.
- Existing `appFrameApplyTimingBucket` covers frame-to-MainActor pressure, but
  it does not distinguish input queue backpressure from local rendering work.
- RFB key and pointer events intentionally share one serial socket queue to
  preserve user order. Measuring queue delay and operation duration with
  coarse buckets keeps that ordering contract while making live diagnostics
  useful enough to debug field reports.

**Verification**:
- `NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport`
  proves outbound input queue/write timings are exported only as safe timing
  buckets and counts.
- `DiagnosticExportTests/testStreamPerformanceReportSanitizesReceiveTimingBuckets`
  and `testStreamPerformanceReportDecodesMissingNewerFieldsAsSafeDefaults`
  prove unsafe bucket values are clamped and older reports default to
  `notMeasured`.
- `PointerEventTapTests/testSendTapAtRecordsOnlySafeOutboundInputDiagnostics`
  proves pointer coordinates stay out of diagnostic JSON while safe outbound
  input counters increment.

**Alternatives considered**:
- Log raw pointer/key events for repro: rejected because coordinates and
  keysyms can reveal user activity and screen content.
- Add exact per-event timing arrays: rejected by the existing diagnostic
  privacy posture; coarse buckets are enough to route freeze triage.
- Measure only at the RFB client write boundary: rejected because it would miss
  queue-delay freezes caused by a previous input event holding the serial tail.

## D34 - Move outbound input serialization out of MainActor

**Decision**: Replace the app-model-owned outbound input tail with a dedicated
lock-backed `OutboundInputEventDispatcher`. `NaruRemoteAppModel` still captures
the active stream, session, profile, and client identity on MainActor, but the
ordered key/pointer task chain, timeout race, and coarse queue/write timing
measurement now run on detached tasks owned by the dispatcher.

**Rationale**:
- Physical iPhone testing still reports that gestures and keyboard input can
  appear frozen immediately after a real VNC connection starts. Even after
  frame decoding and steady frame delivery moved away from SwiftUI frame-diff
  cadence, the input path still kept its serial tail and timeout race as
  app-model state.
- RFB uses one socket for framebuffer control, pointer events, and key events,
  so key/pointer messages must remain ordered. The dispatcher preserves that
  ordering while keeping tail chaining and timeout work off MainActor.
- SwiftUI gesture callbacks necessarily enter on MainActor, but after the
  model maps the gesture to a safe wire command, enqueue must be short and
  non-blocking so video/frame pressure has less chance to delay later input.

**Verification**:
- `DirectKeystrokeModeTests/testTapDirectKeyReturnsBeforeSlowWireWritesAndKeepsOrder`
  proves direct-key taps return before slow wire writes while preserving key
  order.
- `DirectKeystrokeModeTests/testTimedOutKeyEmissionReleasesOutboundQueueForLaterPointerInput`
  proves a stuck key write releases the outbound path for later pointer input.
- `PointerEventTapTests/testRapidTapsStaySerializedAsClickPairsWhenWritesAreSlow`
  proves rapid pointer taps still serialize as click pairs with diagnostics
  samples after the dispatcher split.

**Alternatives considered**:
- Make the dispatcher a Swift actor: deferred because sync enqueue from
  MainActor preserves user-event order more predictably than spawning a new
  task only to await an actor enqueue call.
- Split key and pointer queues: rejected because RFB wire order across key and
  pointer events matters for mixed interactions such as modifier plus click.
- Keep the tail on the app model and rely on diagnostics only: rejected because
  diagnostics help triage but do not reduce the executor coupling seen in live
  physical-device reports.

## D35 - Keep helper-video sample preparation off MainActor

**Decision**: Make `HelperVideoAccessUnitRendering` async and move helper-video
H.264 sample preparation behind a dedicated
`HelperVideoH264SampleBufferPreparationPipeline` actor. The actor owns the
mutable H.264 format cache and performs Annex-B parsing, parameter-set handling,
AVCC conversion, `CMBlockBuffer` allocation/copy, and
`CMSampleBufferCreateReady`. The renderer then returns to MainActor only for
`AVSampleBufferDisplayLayer` status checks, flush, and enqueue. The VNC
frame-application worker loop also now runs as a detached task so queue waits
and pacing sleeps do not live on the UI executor.

**Rationale**:
- Physical iPhone testing reported that the app could freeze immediately after
  an actual connection started, with gestures and keyboard input no longer
  accepted. After previous frame-store and input-dispatcher splits, the next
  suspicious coupling was helper-video sample preparation and frame-application
  pacing still sharing the UI executor.
- `CMSampleBuffer` itself is not Sendable, so the actor returns it in a narrow
  explicit wrapper and the renderer consumes it immediately on MainActor. This
  keeps the non-Sendable display object boundary small while moving the CPU and
  allocation work out of the gesture/input lane.
- H.264 parameter-set state must remain serial. An actor preserves that
  sequence without forcing every access unit through a synchronous MainActor
  method.

**Verification**:
- `HelperVideoStreamSessionRunnerTests/testAsyncRendererPreparationYieldsMainActorDuringAccessUnitEnqueue`
  proves an async renderer can suspend while a MainActor probe still runs.
- `HelperVideoH264SampleBufferRendererTests/testRendererUsesAspectResizeAndIgnoresParameterSetOnlyAccessUnit`
  covers the async renderer API while preserving parameter-set-only behavior.
- `swift test --filter HelperVideoStreamSessionRunnerTests` and
  `swift test --filter HelperVideoH264SampleBufferRendererTests` passed after
  the split.

**Alternatives considered**:
- Keep the renderer protocol synchronous and only lower helper-video frame
  count: rejected because a single large access unit can still monopolize the
  UI executor during sample preparation.
- Move the display layer itself off MainActor: rejected because UIKit/AV layer
  mutation should stay on the UI boundary; only sample preparation is moved.
- Drop the H.264 format cache and prepare each frame independently: rejected
  because parameter-set handling is part of stream correctness.

## D36 - Measure MainActor responsiveness during live streams

**Decision**: Add a lightweight MainActor heartbeat for active VNC streams. The
monitor sleeps at a fixed coarse cadence and records only aggregate
responsiveness sample count plus average/max delay buckets in
`DiagnosticStreamPerformanceReport`.

**Rationale**:
- Physical iPhone testing improved after frame, input, and helper-video work
  moved off the UI executor, but a real connection could still make gestures or
  the Compose dock feel frozen. Existing network/decode/app-apply/input queue
  buckets cannot prove whether MainActor itself stopped getting scheduled.
- A MainActor task that sleeps and compares actual wake time to the expected
  wake time detects UI-executor starvation without doing work while it sleeps.
- The export remains privacy-safe: no exact millisecond values, frame content,
  dimensions, endpoints, coordinates, keysyms, text, or raw errors leave memory.

**Verification**:
- `NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport`
  proves responsiveness samples become only timing buckets and counts.
- `DiagnosticExportTests/testStreamPerformanceReportSanitizesReceiveTimingBuckets`
  and `testStreamPerformanceReportDecodesMissingNewerFieldsAsSafeDefaults`
  prove unsafe or missing responsiveness fields clamp to safe defaults.
- `NaruRemoteAppModelTests` passed after the stream-lifecycle monitor was
  added.

**Alternatives considered**:
- Export exact heartbeat delays: rejected because existing diagnostics use
  coarse timing buckets and exact values are not needed for first triage.
- Run the heartbeat as a detached task that hops into `MainActor.run`:
  rejected because Swift 6 strict concurrency flags task-isolated `self`
  crossing into a main-actor closure; a MainActor sleeping task measures the
  same wake delay with less concurrency risk.
- Infer UI freezes only from app-frame apply timing: rejected because frame
  publication can be healthy while gesture/keyboard scheduling is still starved.

## D37 - Gate ScreenCaptureKit app bootstrap separately from VNC readiness

**Decision**: Add a fixed
`helper-screen-app-bootstrap-benchmark` runner that exercises finite
ScreenCaptureKit access units through helper TCP framing, app-model
helper-video bootstrap, and the H.264 sample-buffer factory without requiring a
live VNC target or printing raw XCTest output.

**Rationale**:
- `remote-desktop-10fps-readiness` already proves the VNC 10fps gate and
  helper probe readiness, but it does not prove that captured helper access
  units can pass through the app model visual-transport bootstrap and sample
  buffer creation path.
- The app-runner XCTest path already proves synthetic helper access units
  through the app bootstrap. Extending it to ScreenCaptureKit keeps the
  remaining T031 risk focused on capture permission/setup and real device
  playback, not on app-model wiring.
- The runner converts XCTest pass/skip/fail into fixed JSON labels so
  permission or capture setup blockers can be collected without exporting
  frame content, dimensions, endpoints, helper paths, raw logs, byte counts, or
  exact timings.

**Evidence**:
- `swift test --filter HelperVideoAppRunnerBenchmarkTests/testNetworkBackedScreenCaptureKitHelperVideoBootstrapThroughAppModelSmoke`
  compiles and skips by default when opt-in benchmark env is absent.
- `scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`
  emits schema `1` JSON and validates with `jq empty`.
- The first local run reports `status=skipped` with fixed
  `screen-capturekit-app-bootstrap-skipped`, which means the benchmark host
  still needs Screen Recording/capture setup before this can become T031 pass
  evidence.

**Privacy rule**: the runner must emit only fixed mode/source/path/status
labels, fixed issue/action labels, and small configured counts. It must not
emit raw XCTest output, frame payloads, pixels, dimensions, endpoints, helper
paths, device IDs, credentials, byte counts, raw OS errors, or exact timings.

## D38 - Treat unavailable physical iPhones as discovery blockers

**Decision**: Tighten `physical-device-preflight` discovery so known but
unavailable physical iPhones are reported as `deviceDiscoveryStatus=unavailable`
and skip the build check instead of being treated as connected devices that
later fail with a generic physical build error.

**Rationale**:
- The physical iPhone gate is the promotion boundary for T030/T031. If a paired
  but unavailable iPhone is classified as connected, the runner spends time in
  an Xcode build that cannot prove product behavior and collapses the actionable
  setup issue into `physical-ios-build-failed`.
- `devicectl` can list an iPhone while its tunnel is unavailable or developer
  disk services are not available. `xctrace` can also list the same device
  under `Devices Offline`. Those states require unlock/cable/network/developer
  mode remediation before any sustained-session evidence is meaningful.
- Skipping the build in this state keeps the artifact privacy-safe and more
  actionable: no raw device identifiers, names, logs, or provisioning details
  are emitted.

**Evidence**:
- `scripts/run-naru-live-benchmark.sh physical-device-preflight` now reports
  `deviceDiscoveryStatus=unavailable`, `buildCheckStatus=skipped`,
  `physical-iphone-device-unavailable`, and
  `unlock-connect-and-enable-developer-mode` in the current local state.
- `scripts/run-naru-live-benchmark.sh physical-team-inference-self-test`
  still passes.
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness` still
  confirms the VNC path fails the 10fps product bar at about 2 content FPS with
  first-byte wait dominating, so helper-video permission plus physical iPhone
  readiness remain the next promotion gates.

**Privacy rule**: physical-device preflight must emit fixed discovery/build
status labels and fixed setup actions only. It must not emit physical device
names, identifiers, serials, raw Xcode logs, provisioning identifiers, host
identity, credentials, pixels, byte counts, exact helper timings, draft text, or
IME state.

## D39 - Summarize physical, helper, and VNC gates in one readiness object

**Decision**: Upgrade `remote-desktop-10fps-readiness` to schema `2` and add a
top-level `physicalDevicePreflight` plus a derived
`readinessGateSummary`. The summary separates wrapper command status from the
inner 10fps product verdict and reports the physical iPhone gate, helper-video
gate, VNC 10fps gate, primary blocked labels, and the recommended next action
in one privacy-safe object. The top-level readiness envelope is schema `2`; the
nested derived summary keeps schema `1` and includes
`parentReadinessSchemaVersion=2` to make the version boundary explicit.

**Rationale**:
- The reproduced live state has three independent blockers: the physical iPhone
  is unavailable, helper-video synthetic transport passes while true
  ScreenCaptureKit capture is permission-blocked, and the VNC 10fps product
  verdict still fails even when the wrapper command succeeds.
- Without a derived summary, a reviewer has to inspect nested helper and VNC
  benchmark reports to notice that `vnc10fpsProbe.status=passed` means the
  benchmark executed, not that the product goal passed.
- The best architecture remains the dual-transport plan: VNC stays connected
  for control/input/fallback, while helper H.264 video is the primary
  smoothness candidate after Screen Recording and physical iPhone gates pass.
- Apple ScreenCaptureKit and VideoToolbox point toward a helper-side capture
  and low-latency H.264 pipeline, while TigerVNC's own viewer documents
  adaptive encoding/pixel-format behavior and pointer rate limiting. That
  supports benchmark-backed profile selection rather than another blind VNC
  default flip.

**Evidence**:
- `bash -n scripts/run-naru-live-benchmark.sh` passes.
- `scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test | jq empty`
  passes and proves the summary classifies physical unavailable, helper
  permission missing, and VNC product failure together.
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness > /tmp/naru-readiness-v2.json`
  emits schema `2` JSON that validates with `jq empty`.
- Current live `readinessGateSummary`: `overallGateState=blockedByHelperScreenCapture`,
  `recommendedPrimaryAction=grant-helper-video-app-screen-recording-permission`,
  blocked labels `physical-iphone-gate-blocked`,
  `helper-video-screen-capture-gate-blocked`, and
  `vnc-10fps-product-gate-failed`.
- Current VNC gate: wrapper status `passed`, product verdict `fail`,
  `1.98` content FPS, `505` ms average update, `628` ms p95 update,
  `619` ms first-byte wait p95, `0` ms payload-read p95, and `8` ms
  client-processing p95.
- The readiness summary deliberately prioritizes helper Screen Recording setup
  over physical iPhone preflight when both are blocked, because true
  ScreenCaptureKit helper-video cannot be benchmarked until the helper app has
  capture permission.

**References**:
- Apple ScreenCaptureKit `SCStreamConfiguration.queueDepth`:
  https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
- Apple VideoToolbox low-latency encoding:
  https://developer.apple.com/documentation/videotoolbox/encoding-video-for-low-latency-conferencing
- TigerVNC viewer options and adaptive selection:
  https://tigervnc.org/doc/vncviewer.html

**Privacy rule**: the readiness summary may emit fixed status/action labels,
fixed issue labels, aggregate FPS/update timing summaries, and aggregate
permission/capability labels only. It must not emit host identity,
credentials, helper executable paths, physical device identifiers, endpoints,
framebuffer dimensions, coordinates, pixels, byte counts, raw command output,
exact helper timings, Compose text, marked text, or IME state.

## D40 - Gate helper-video on sustained external synthetic H.264, not smoke only

**Decision**: Add a sustained external helper-video probe that starts the real
helper process with a configurable synthetic H.264 frame budget and validates a
full finite batch through the TCP client. Keep the two-frame external synthetic
probe as smoke only, but use `external-helper-sustained-synthetic-encoded-tcp`
for readiness and short live comparison gates. Split VideoToolbox encoding into
`completeFrameBatch` for deterministic synthetic probes and
`lowLatencyRealtime` for ScreenCaptureKit capture, and scale ScreenCaptureKit
timeouts by requested frame count.

**Rationale**:
- A two-frame helper-video smoke probe can pass while the sustained path still
  fails before transport health is meaningful.
- Reproducing the issue at six synthetic frames showed that VideoToolbox
  low-latency rate control can drop synthetic batch frames; for benchmark
  transport validation that is the wrong policy. Synthetic sustained probes
  should prove helper process, H.264 access-unit framing, and TCP delivery
  deterministically.
- Real ScreenCaptureKit streaming should keep the low-latency realtime policy,
  where dropping late frames is preferable to blocking UI/input.
- The benchmark wrapper can be misled by a stale launchctl helper executable.
  External helper failures now map to fixed safe issue labels such as
  `helper-video-external-helper-unavailable`,
  `helper-video-external-helper-timed-out`, or
  `helper-video-transport-failed` instead of collapsing into a generic failed
  helper-video report.
- Direct key-event write timeout must not permanently disable the key emitter.
  A timeout should record diagnostics while allowing later key events in the
  same session to recover.

**Evidence**:
- Before this change, `helper-synthetic-probe` passed but
  `helper-sustained-synthetic-probe` failed with
  `helper-video-startup-failed` and `helper-video-sustained-stalled`.
- `swift test --filter
  NaruHelperVideoEncoderPrototypeTests/testToolboxSyntheticAccessUnitSourceEmitsSustainedFrameBatch`
  now passes and proves the synthetic VideoToolbox source emits a sustained
  Annex B access-unit batch.
- `swift test --filter
  NaruHelperVideoListenRuntimeTests/testExternalHelperProcessSendsSustainedSyntheticEncodedBatch`
  now passes and proves a real helper process can send the sustained synthetic
  batch through TCP.
- `scripts/run-naru-live-benchmark.sh helper-sustained-synthetic-probe` now
  emits a helper-video report with `streamState=healthy`,
  `startupBand=fast`, `sustainedUpdateBand=smooth`,
  `codecProfile=high`, and empty issue codes after the launchctl helper path is
  refreshed to the current SwiftPM helper artifact.
- Running the same wrapper against the stale helper executable no longer hides
  the cause completely; the report includes fixed
  `helper-video-transport-failed` in addition to derived failed health labels.

**Privacy rule**: sustained helper-video benchmark artifacts may include fixed
mode names, fixed issue labels, coarse health bands, codec catalog labels, and
aggregate pass/fail verdicts only. They must not include helper executable
paths, launchctl values, host identity, endpoints, credentials, physical device
identifiers, framebuffer dimensions, pixels, byte counts, exact timings,
stderr/stdout, Compose text, marked text, or IME state.

## D41 - Make helper app setup a privacy-safe benchmark mode

**Decision**: Add `scripts/run-naru-live-benchmark.sh helper-dev-app-setup` as
the setup bridge before true ScreenCaptureKit helper-video gates. The mode
builds and installs the local development helper app wrapper, sets the
launchctl helper executable, runs the explicit Screen Recording permission
request, optionally opens System Settings, and emits one privacy-safe JSON
object with fixed install/signing/env labels and helper capability responses.

**Rationale**:
- True helper-video capture is blocked by Screen Recording permission, and the
  permission identity must be the stable helper app bundle, not an arbitrary
  SwiftPM executable path.
- The existing install script is useful for humans but prints helper paths.
  A benchmark-mode wrapper lets us collect setup evidence without leaking
  helper paths, team identifiers, raw install logs, endpoints, credentials,
  pixels, byte counts, or exact timings.
- The mode does not claim permission is granted. When macOS returns
  `notGranted`, it records `helper-video-permission-missing` and setup action
  `grant-helper-video-app-screen-recording-permission`, keeping the remaining
  action crisp.
- This reduces false diagnosis in `remote-desktop-10fps-readiness`: synthetic
  helper-video can stay green, VNC can remain first-byte-wait dominated, and
  true ScreenCaptureKit failure can be routed to the correct app-bundle
  permission gate.

**Evidence**:
- `NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip
  scripts/run-naru-live-benchmark.sh helper-dev-app-setup` emits schema `1`
  JSON with `installStatus=passed`, `codeSigningStatus=appleDevelopment`,
  `launchctlEnvStatus=set`, `helperProcessKind=appBundle`,
  `screenRecordingPermission=missing`, and setup action
  `grant-helper-video-app-screen-recording-permission`.
- `scripts/run-naru-live-benchmark.sh helper-readiness-sweep` after setup
  reports `processKind=appBundle`, `synthetic=pass`, `sustained=pass`, and
  `screenVerdict=fail` while Screen Recording remains missing.

**Privacy rule**: helper app setup reports may include fixed install status,
fixed code signing class, launchctl env status, helper process kind,
capability catalog labels, fixed issue codes, and fixed setup action labels
only. They must not include helper executable paths, app paths, team
identifiers, signing identity names, raw install logs, host identity,
endpoints, credentials, physical device identifiers, pixels, byte counts,
exact timings, stderr/stdout, Compose text, marked text, or IME state.

## D42 - Defer live-session dock transitions while Compose owns IME focus

**Decision**: Treat the UIKit Compose editor as an input island across VNC
first-frame and session-activation churn. While Compose is focused and Direct
mode is inactive, `RemoteInputDockRenderState` equality ignores model-mirrored
draft text, helper-status text, standard-to-compact dock layout changes, sticky
modifier state, and Compose quick-key availability. Send-result status remains
visible and still repaints the dock while focused.

**Rationale**:
- The current physical-device symptom is not just low FPS; the user reports
  Korean Compose accepting one character and then appearing frozen after a real
  connection starts.
- A focused repro showed that a first frame arriving during input changes the
  derived dock state from pre-live standard layout with no quick keys to live
  compact layout with quick keys. That transition is useful when the editor is
  idle, but it is the wrong boundary while UIKit owns marked-text state.
- Deferring accessory/layout invalidation keeps the `UITextView` bridge stable
  during IME composition without losing the app-model mirror, diagnostics, or
  Send result visibility. Once focus leaves, the live-session compact layout
  and quick-key strip can appear normally.
- This fits the broader dual-transport design: visual-stream state may change
  independently, but local input responsiveness is product-critical and must
  not depend on VNC first-byte cadence or helper-video readiness.

**Evidence**:
- Before the fix,
  `swift test --filter RemoteInputDockRenderStateTests/testFocusedInputDockRenderStateDefersLiveSessionLayoutTransition`
  failed with `layoutStyle: standard -> compactAccessory` and
  `showsComposeQuickKeys: false -> true` while the focused Compose text was
  unchanged.
- After the fix, `swift test --filter RemoteInputDockRenderStateTests` passes.
- `swift test --filter RemoteInputDockSyncPolicyTests` also passes, preserving
  the existing marked-text adoption, binding-write deferral, and send
  stabilization contract.
- `swift test` passes with 1188 tests executed and 14 benchmark/device-gated
  tests skipped.
- The iPhone 17 Pro simulator UI test
  `NaruRemoteUITests/ComposeInputResponsivenessUITests` passes both the
  active-session compact Compose path and the profile-detail Compose path,
  typing a second Korean syllable after the first input.

**Privacy rule**: Compose input isolation tests and artifacts use fixed UI
state labels and synthetic text only. They must not emit live draft text,
marked text, keysyms, pointer coordinates, host identity, credentials,
framebuffer pixels, dimensions, byte counts, raw timings, raw OS errors, or
helper endpoints.

## D43 - Surface helper-video readiness before the user enters a session

**Decision**: Connection-grid cards show a compact helper-video readiness badge
derived from fixed `HelperVideoProfileState` catalog values. Profile edits that
come from the current editor preserve an existing `helperVideo` configuration
unless a dedicated helper-video disable/revoke path changes it.

**Rationale**:
- The current live 10fps gate is not ambiguous: VNC remains below the product
  target because first-byte wait dominates, synthetic H.264 helper-video is
  smooth, and true ScreenCaptureKit capture is blocked by the helper app
  bundle's missing Screen Recording permission.
- If this state is visible only in benchmark JSON, users can keep trying a
  VNC visual path that cannot reach the sustained iPhone target in the current
  environment. The first screen should reveal whether a profile is `VNC only`,
  `Helper video`, or blocked at `Screen Recording`.
- The existing profile editor currently owns VNC and helper text fields, but
  helper video enable/disable/revoke is handled elsewhere. Until a full
  helper-video editor exists, editing a profile must not silently remove the
  opt-in smooth visual transport candidate.
- The badge stays privacy-safe by exposing only fixed labels and accessibility
  text. It does not expose helper endpoints, tokens, pairing fingerprints,
  hostnames, frame metadata, dimensions, byte counts, timings, or raw errors.

**Evidence**:
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness` reports
  `overallGateState=blockedByHelperScreenCapture`,
  `recommendedPrimaryAction=grant-helper-video-app-screen-recording-permission`,
  synthetic and sustained synthetic helper-video `pass`, ScreenCaptureKit
  helper-video `helper-video-permission-missing`, and VNC
  `contentFramesPerSecond=1.83` with `firstByteWaitP95Milliseconds=632`.
- `swift test --filter NaruRemoteAppSnapshotTests` verifies grid readiness
  labels and that labels/accessibility text do not include pairing
  fingerprints, helper token references, or hostnames.
- `swift test --filter
  ProfileEditDeleteTests/testEditProfilePreservesExistingHelperVideoConfiguration`
  verifies profile edits preserve the existing helper-video configuration and
  readiness state.

**Privacy rule**: helper-video readiness UI may show only fixed labels,
catalog-derived state, and setup action concepts. It must not show helper
endpoints, helper executable paths, pairing secrets, pairing fingerprints,
hostnames, physical device identifiers, provisioning details, pixels,
dimensions, byte counts, coordinates, exact per-frame timings, raw OS errors,
Compose text, clipboard contents, or access-unit payloads.

## D44 - Keep post-send status changes out of the focused Compose editor host

**Decision**: Treat every model-mirrored field as advisory while UIKit owns
Compose focus, including send-result status. The focused dock now strips
status/helper text out of the `RemoteInputDockEquatableHost` state and shows
actionable status in a sibling `FocusedComposeStatusLine`, so status can update
without invalidating the `UITextView` bridge.

**Rationale**:
- The latest user repro was not just first-frame layout churn. After a send
  result such as "remote app confirmation unavailable" is visible, typing the
  next Korean syllable calls `updateComposeDraftText`, which clears
  `latestInjectionAttempt`. The old render-state equality treated that status
  clear as a focused dock repaint, which can disturb the IME chain right after
  the first syllable commits.
- Status visibility is useful, but it is not allowed to share identity with the
  hot input editor. Splitting it into a sibling view preserves feedback while
  making the editor host immune to send-status arrival, status clear, helper
  text changes, VNC frame arrival, quick-key availability, and compact-layout
  transitions.
- This follows the same architecture as frame-store isolation: high-cadence or
  asynchronous remote/session state must not become a reason to recreate local
  input infrastructure.

**Evidence**:
- Before the fix,
  `swift test --filter RemoteInputDockRenderStateTests/testFocusedInputDockRenderStateDefersStatusClearAfterTypingOverPreviousSendResult`
  failed because `statusText` changed from confirmation-unavailable to ready
  and `showsCompactStatusText` changed from true to false while Compose focus
  was active.
- After the fix, `swift test --filter RemoteInputDockRenderStateTests` and
  `swift test --filter RemoteInputDockSyncPolicyTests` pass.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination
  'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests test`
  passes both the active compact and profile-detail Korean second-syllable
  flows.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination
  'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
  -only-testing:NaruRemoteUITests/NaruRemoteLaunchUITests test` passes after
  updating stale launch expectations to the current grid-first/empty-home UI.

**Privacy rule**: focused status isolation tests may use fixed UI labels and
synthetic Korean text only. They must not export live Compose drafts, marked
text, clipboard contents, keysyms, pointer coordinates, host identity,
credentials, frame pixels, dimensions, byte counts, exact timings, raw OS
errors, helper endpoints, or device identifiers.

## D45 - Compare VNC request/response with ContinuousUpdates before more profile flips

**Decision**: Add a fixed
`scripts/run-naru-live-benchmark.sh remote-desktop-10fps-transport-cadence-drilldown`
mode. The runner holds `local-low-latency-rgb565`, local network condition,
phone-portrait viewport requests, `visible-glance`, `0.25` startup scale, depth
`1`, and `iphone-remote-desktop-10fps-v1` fixed while comparing
`request-response` against `continuous-updates`.

**Rationale**:
- Current VNC profile and server-cadence sweeps show the same pattern:
  profile-only changes do not reach the 10fps bar, successful samples are
  dominated by receive-path first-byte wait, and payload/client/renderer costs
  are not the main constraint.
- RFC 6143 makes request/response demand-driven, so first-byte wait can be a
  protocol/server cadence ceiling rather than an app rendering problem.
  ContinuousUpdates is the relevant RFB extension to test before assuming a
  client-side transport flip can solve sustained smoothness.
- If ContinuousUpdates cannot produce samples on the current Mac Screen
  Sharing target, VNC remains control/input/fallback while the smooth visual
  path needs helper-video Screen Recording approval and true helper-video live
  capture evidence.

**Evidence**:
- `bash -n scripts/run-naru-live-benchmark.sh` passes.
- `scripts/run-naru-live-benchmark.sh --help` lists
  `remote-desktop-10fps-transport-cadence-drilldown`.
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-transport-cadence-drilldown -- --stream-shape-samples 1`
  rejects extra arguments with a fixed mode error.
- A live `remote-desktop-10fps-transport-cadence-drilldown` run exits `rc=0`
  and emits JSON accepted by `jq empty`.
- Live result: request/response fails the 10fps target with `5.97` content FPS,
  `7.05` delivered FPS, `132` ms average update, `502` ms p95 update, and
  `502` ms p95 first-byte wait. ContinuousUpdates fails before usable samples
  with `probe-failed`.
- `screen-recording-setup` reports `permissionMissing`, permission request
  `notGranted`, settings status `opened`, and `permissionMissing` after the
  request.

**Privacy rule**: the runner and artifacts emit only fixed mode/candidate,
profile, target, transport, network, request, setup, verdict, issue, and action
labels plus aggregate benchmark values. They must not export host identity,
credentials, ports, helper paths, executable paths, command lines, raw
stdout/stderr, raw TCP/RFB errors, raw OS errors, coordinates, dimensions,
pixels, byte counts, stimulus command text, Compose text, marked text, IME
state, keysyms, helper endpoints, pairing material, or physical device IDs.

## D46 - Prefer reachable helper text insertion over VNC clipboard paste

**Decision**: When a helper text bridge is enabled, reachable, and matched by a
reachable helper insert client or stored helper profile, Compose delivery uses
`helperTextBridge` for every non-empty payload. This includes ASCII, Latin-1,
and VNC UTF-8-supported payloads. VNC clipboard + paste remains the fallback
when helper text insertion is absent, disabled, revoked, unreachable, or not yet
known reachable; stored-helper probing remains allowed for UTF-8 payloads that
VNC cannot send safely.

**Rationale**:
- The user-visible `Remote app confirmation unavailable` status is not a real
  delivery guarantee. Physical feedback showed the app could report that state
  while remote text still did not appear.
- Clipboard + paste depends on remote focus, remote clipboard adoption timing,
  VNC server UTF-8 behavior, and the remote app accepting the paste shortcut.
  Those are useful compatibility fallbacks but too ambiguous for the primary
  multilingual Compose path once helper insertion is ready.
- Helper insertion is already the product direction for reliable local
  composition. Making it helper-first aligns diagnostics, preflight, and actual
  send behavior instead of reserving helper only for VNC UTF-8 failures.

**Evidence**:
- `swift test --filter
  NaruRemoteAppModelTests/testModelPrefersReachableHelperForComposePayloadsEvenWhenVNCPasteCouldRun`
  proves a reachable helper handles both ASCII and Korean/CJK/emoji Compose
  payloads while VNC clipboard payloads and paste commands remain empty.
- `swift test --filter NaruRemoteAppModelTests/testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed`
  preserves the existing helper path for unconfirmed VNC UTF-8 support.
- `swift test --filter NaruRemoteAppModelTests/testModelSendsComposedTextThroughActiveRFBTextClientAfterConnect`
  preserves VNC clipboard + paste fallback when helper text insertion is not
  configured.

**Privacy rule**: Compose route diagnostics and tests may include only fixed
route names, payload-encoding classes, helper availability classes, and
aggregate pass/fail state. They must not export live Compose text, marked text,
clipboard contents, keysyms, helper endpoints, pairing material, host identity,
credentials, device identifiers, raw VNC/helper errors, pixels, dimensions, or
byte counts.
