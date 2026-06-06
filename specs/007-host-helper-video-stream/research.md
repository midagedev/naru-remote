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
