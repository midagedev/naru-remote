# Quickstart: Host Helper Video Stream

This feature is implemented in small foundation slices. Use the implemented
checks first, then the planned checks as each later task lands.

## Readiness

```bash
rg -n "NEEDS CLARIFICATION" specs/007-host-helper-video-stream
```

Expected: no matches.

## Implemented Foundation Tests

```bash
swift test --filter HelperVideo
swift test --filter HelperVideoFakeTransportTests
swift test --filter DiagnosticExportTests
swift test --filter BenchmarkHelperVideoReportTests
swift test --filter BenchmarkVisualTransport
swift test --filter ConnectionProfileTests
```

## Implemented App Model Tests

```bash
swift test --filter NaruRemoteAppModelTests/testModelSelectsHelperVideoVisualTransportForPairedReachableProfile
swift test --filter NaruRemoteAppModelTests/testHelperVideoStallFallsBackToVNCWithoutClearingComposeDraft
swift test --filter NaruRemoteAppModelTests/testNoHelperVideoProfileKeepsVNCBaselineAndReportsSafeDiagnosticState
swift test --filter NaruRemoteAppModelTests/testPublicHostProfileBlocksHelperVideoWithPrivateNetworkReason
swift test --filter NaruRemoteAppModelTests/testStoredHelperVideoProfileInitializesPrivateNetworkStateWhenLoadingProfiles
swift test --filter NaruRemoteAppModelTests/testStoredPublicHostHelperVideoInitializesPrivateNetworkRequiredState
swift test --filter NaruRemoteAppModelTests/testDisableAndRevokeHelperVideoFallsBackWithoutDroppingSession
swift test --filter NaruRemoteAppModelTests/testDisableAndRevokeHelperVideoPersistThroughProfileReload
swift test --filter NaruRemoteAppModelTests/testRevokeHelperVideoKeepsCredentialWhenProfilePersistenceFails
```

## Implemented Helper Video Probe

```bash
swift build --product NaruHelper
swift test --filter NaruHelperVideo
.build/debug/NaruHelper --video-capability
.build/debug/NaruHelper --video-request-screen-recording-permission
.build/debug/NaruHelper --video-capability
```

`--video-capability` emits only fixed catalog labels such as
`permissionMissing`, `granted`, `notChecked`, `available`, or `unavailable`.
It must not emit display identifiers, dimensions, window names, endpoints,
host names, byte counts, frame content, or exact timings.
`--video-request-screen-recording-permission` is the explicit permission
request entrypoint for development and manual setup. It may show the macOS
Screen Recording prompt, emits only fixed catalog labels such as `granted` or
`notGranted`, and should be followed by `--video-capability` after any required
helper/app relaunch.

## Implemented Helper Video Encoder Prototype

```bash
swift build --product NaruHelper
swift test --filter NaruHelperVideoEncoder
.build/debug/NaruHelper --video-encoder-prototype
NARU_HELPER_VIDEO_ENCODER_PROTOTYPE=1 .build/debug/NaruHelper --video-encoder-prototype
```

`--video-encoder-prototype` emits only fixed catalog labels. With the feature
flag disabled, it must not create a VideoToolbox compression session. With the
feature flag enabled, it prepares a synthetic low-latency H.264 session and
must not emit dimensions, encoded payloads, byte counts, host names, endpoints,
display names, frame content, or exact timings.

## Implemented Helper Video Auth Transport Slice

```bash
swift test --filter NaruHelperVideoTransport
```

The helper-video transport slice signs app-to-helper request envelopes with an
HMAC-SHA256 `authProof` scoped to request ID, message type, and profile
fingerprint. Helper responses omit `authProof` and must not echo pairing
secrets, encoded payloads, dimensions, byte counts, host names, endpoints, or
display names. This slice handles authenticated `capabilityRequest` and
`startStream` frames plus shared authorization for `requestKeyframe` and
`stopStream`; it does not send live access units yet.

## Implemented Helper Video Access-Unit Pipeline

```bash
swift test --filter NaruHelperVideoStreamFramePipeline
swift test --filter HelperVideoH264SampleBufferRendererTests/testHelperPipelineAccessUnitsFeedIOSSampleBufferFactory
```

The helper-side pipeline accepts an authenticated `startStream` frame, emits a
safe `startStream` response, then emits length-prefixed `videoAccessUnit`
frames with binary payload outside JSON. If an accepted stream has no access
units, it emits a safe `streamStalled` frame for VNC fallback. It is still a
testable frame pipeline, not a live ScreenCaptureKit/VideoToolbox sender.

## Implemented Helper Video TCP Harness

```bash
swift test --filter NaruHelperVideoStreamNetworkService
swift test --filter NaruHelperVideoListenRuntimeTests
```

The prototype TCP harness connects the helper-side frame pipeline to an
`NWListener` and a finite `HelperVideoStreamNetworkClient` batch reader. It is
for local integration and benchmark bring-up: it sends authenticated
`startStream` requests, receives safe start responses, drains access-unit or
stall frames, and closes the connection after the finite batch. It is not yet
the long-lived live ScreenCaptureKit/VideoToolbox sender.

## Implemented Helper Video Listen Entrypoint

```bash
swift build --product NaruHelper
export NARU_HELPER_VIDEO_TOKEN="<pairing-secret-from-keychain-or-local-test>"
export NARU_HELPER_VIDEO_PROFILE_FINGERPRINT="sha256:<saved-profile-fingerprint>"
.build/debug/NaruHelper \
  --video-listen \
  --token-env NARU_HELPER_VIDEO_TOKEN \
  --profile-fingerprint-env NARU_HELPER_VIDEO_PROFILE_FINGERPRINT \
  --port 5975 \
  --video-source synthetic-encoded \
  --video-frame-count 2
```

`--video-listen` starts the same authenticated helper-video TCP server used by
the tests and benchmark probes. `--video-source synthetic-encoded` uses local
VideoToolbox H.264 output for safe loopback smoke tests. `--video-source
screen-capturekit` uses a finite ScreenCaptureKit batch and requires Screen
Recording permission in the helper process context. This entrypoint is still a
finite batch sender per `startStream` request, not the final long-lived adaptive
desktop stream. Prefer `--token-env` and `--profile-fingerprint-env` so
sensitive values are not exposed through helper process arguments. It must not
print pairing secrets, endpoints, frame payloads, display dimensions, byte
counts, host names, raw OS errors, or exact timings.

## Implemented Helper Video Benchmark TCP Probe

```bash
swift build --product NaruHelper

NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 0 \
  --visual-transport helper-video \
  --helper-video-probe synthetic-encoded-tcp \
  --json
```

`--helper-video-probe synthetic-tcp` runs a local finite helper-video TCP
harness with static access units. `synthetic-encoded-tcp` uses local
VideoToolbox H.264 output as the access-unit source before sending it through
the same finite TCP harness. `screen-capturekit-tcp` captures a finite batch of
ScreenCaptureKit frames, converts their `CVPixelBuffer` images through the same
VideoToolbox encoder, and sends those access units through the local TCP
harness. `external-helper-synthetic-encoded-tcp` launches
`.build/debug/NaruHelper --video-listen` with env-indirected synthetic pairing
state, then connects the benchmark's helper-video network client to that
external helper process. Override the helper executable with
`NARU_HELPER_EXECUTABLE` when testing a packaged helper build; Xcode smoke
runs may also use the `BUILT_PRODUCTS_DIR` or `CONFIGURATION_BUILD_DIR`
fallback for the built `NaruHelper` binary.
`external-helper-screen-capturekit-tcp` uses the same external helper process
path with `--video-source screen-capturekit`; it should be used only when the
helper process context has Screen Recording permission. These modes report only
fixed helper-video labels and aggregate health bands; reports must not include
helper executable paths, environment variable names or values, endpoints, frame
payloads, byte counts, dimensions, raw errors, or exact timings. The default
remains `disabled` so live VNC reports do not imply a long-lived
ScreenCaptureKit sender before it exists.

```bash
swift build --product NaruHelper

NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 0 \
  --visual-transport helper-video \
  --helper-video-probe external-helper-synthetic-encoded-tcp \
  --json
```

```bash
swift build --product NaruHelper

NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 0 \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

## Implemented iOS H.264 Decode / Display Prototype

```bash
swift test --filter HelperVideoH264
```

The iOS prototype accepts helper-video `videoAccessUnit` frames with binary
Annex-B H.264 payloads, caches SPS/PPS parameter sets through CoreMedia,
converts displayable access units to AVCC `CMSampleBuffer` values, and exposes
an `AVSampleBufferDisplayLayer` renderer. It must not log or export payload
bytes, frame content, dimensions, byte counts, host names, endpoints, pairing
secrets, or exact per-frame timings.

## Implemented App-Side Helper Video Session Runner

```bash
swift test --filter HelperVideoStreamSessionRunnerTests
```

The app-side session runner applies a finite helper-video network start result
to the active app session: accepted streams select helper video only when the
profile/session gate allows it, displayable access units pass through the iOS
renderer, and start rejection, stream stalls, decoder rejection, or transport
failure fall back to VNC visual state. It reports only fixed catalog failure
codes and coarse helper health; it must not export helper endpoints, access-unit
payloads, byte counts, display dimensions, exact timings, raw OS/network errors,
host names, pairing secrets, Compose text, clipboard contents, or frame content.

## Planned Live Benchmark Shape

The live password must be supplied only through the existing environment path.
Do not pass it as a command-line literal.

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --visual-transport vnc,helper-video \
  --json
```

The helper-video side of the report is still benchmark-only until the long-lived
helper sender/listener is connected. Use `--helper-video-probe
synthetic-encoded-tcp` when the benchmark should exercise real local
VideoToolbox H.264 access units without exporting frames, dimensions,
endpoints, byte counts, or exact timings. Use `--helper-video-probe
external-helper-synthetic-encoded-tcp` when the benchmark should launch the
real `NaruHelper --video-listen` process before connecting the helper-video
client with deterministic VideoToolbox output. Use `--helper-video-probe
external-helper-screen-capturekit-tcp` when the same external helper process
should exercise finite ScreenCaptureKit capture. Use `--helper-video-probe
screen-capturekit-tcp` only when the local benchmark process has Screen
Recording permission and the run should exercise a finite real screen-capture
batch through the same safe aggregate report boundary. Reports must preserve
the privacy boundary from `spec.md` and `research.md`.

When Screen Recording permission is missing, `screen-capturekit-tcp` and
`external-helper-screen-capturekit-tcp` report the fixed issue code
`helper-video-permission-missing` and must not start capture or emit raw OS
error text.

## Planned Physical Gate

- Physical iPhone first.
- Mac helper paired on a private-network profile.
- 30 minute terminal or AI CLI watch session.
- Record only redacted notes:
  - fixed candidate labels
  - startup readability result
  - sustained smoothness result
  - fallback count bucket
  - thermal comfort bucket
  - Compose reliability result

Do not commit screenshots, screen recordings, host names, helper endpoints,
frame content, byte counts, coordinates, or exact per-frame timings by default.
