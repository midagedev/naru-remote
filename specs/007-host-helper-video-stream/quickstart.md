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
swift test --filter NaruRemoteAppModelTests/testHelperVideoBootstrapStartsAfterVNCFirstFrameWithoutDroppingControl
swift test --filter NaruRemoteAppModelTests/testHelperVideoBootstrapFailureKeepsVNCFrameAndControlPathActive
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
host names, byte counts, frame content, executable paths, or exact timings.
The schema `2` response also includes fixed `permissionIdentity` labels. For
example, `processKind=swiftPMBuildArtifact` with
`grantHint=useStableHelperExecutable` means the current development helper
binary is not a stable permission target; copy/package the helper into a stable
location or app bundle before requesting Screen Recording permission for longer
live benchmark runs.
For local development, install the stable dev app wrapper and point future
benchmark shells at it:

```bash
scripts/install-naru-helper-dev-app.sh --set-launchctl-env --request-permission
```

By default, the installer uses exactly one local Apple Development signing
identity when available and otherwise falls back to ad-hoc signing. It reports
only a fixed signing label such as `appleDevelopment`, `adHoc`, or `explicit`;
set `NARU_HELPER_DEV_CODESIGN_IDENTITY` or pass `--signing-identity` when a
specific local identity is needed.
After this, helper diagnostics should report `processKind=appBundle` and
`grantHint=grantAppBundle`. If Screen Recording is still `missing`, grant
Screen Recording to `NaruHelperDev` in macOS System Settings, relaunch the
helper, and rerun `--video-capability`.
`--video-request-screen-recording-permission` is the explicit permission
request entrypoint for development and manual setup. It may show the macOS
Screen Recording prompt, emits only fixed catalog labels such as `granted` or
`notGranted`, and should be followed by `--video-capability` after any required
helper/app relaunch. Its schema `2` response carries the same
`permissionIdentity` labels as `--video-capability`.

## Implemented Launchctl-Backed Live Benchmark Runner

Use the wrapper when live benchmark credentials and helper paths are already
stored in `launchctl` environment variables. It imports values into the child
process only and never prints the variable values.

```bash
scripts/run-naru-live-benchmark.sh preflight
scripts/run-naru-live-benchmark.sh helper-synthetic-probe
scripts/run-naru-live-benchmark.sh helper-screen-probe
scripts/run-naru-live-benchmark.sh helper-readiness-sweep
scripts/run-naru-live-benchmark.sh screen-recording-setup
scripts/run-naru-live-benchmark.sh physical-device-preflight
scripts/run-naru-live-benchmark.sh physical-team-inference-self-test
scripts/run-naru-live-benchmark.sh short-live-comparison
scripts/run-naru-live-benchmark.sh glance-scale-sweep
scripts/run-naru-live-benchmark.sh glance-025-duration-probe
scripts/run-naru-live-benchmark.sh glance-025-profile-sweep
scripts/run-naru-live-benchmark.sh helper-capability
scripts/run-naru-live-benchmark.sh request-screen-recording
```

The modes emit the same privacy-safe JSON/report output as the underlying
tools. `helper-synthetic-probe` does not require live VNC target credentials.
`helper-screen-probe` and `preflight` are the fastest checks after granting
Screen Recording to `NaruHelperDev`. `short-live-comparison` is a compact
constrained-cellular VNC plus external synthetic helper-video gate for ongoing
fallback and traffic work.
`helper-readiness-sweep` emits one JSON object containing helper capability,
environment preflight, external synthetic helper-video, and external
ScreenCaptureKit helper-video probe reports. It rejects additional arguments so
the readiness gate remains repeatable. If a sub-step exits before returning
JSON, the sweep emits only that step's fixed label and fixed safe failure code;
it does not print raw helper stderr, credential values, helper paths,
endpoints, payloads, byte counts, dimensions, raw OS errors, or exact timings.
`screen-recording-setup` checks helper capability, runs the explicit helper
permission request, opens macOS Screen Recording settings, and checks helper
capability again. It emits only fixed setup/status labels. In automation, set
`NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip` to verify the JSON shape
without opening System Settings. After granting Screen Recording to
`NaruHelperDev`, relaunch the helper and rerun `helper-readiness-sweep`.
`physical-device-preflight` checks whether a physical iPhone can be selected
for the T030/T031 gate and whether Xcode signing/provisioning can build the app.
Physical iPads and other non-iPhone devices are not accepted for this gate.
It emits only fixed labels such as `connected`, `ios-development-team-missing`,
`xcode-account-missing`, and `ios-provisioning-profile-missing`; it must not
print device names, device IDs, provisioning profile names, bundle identifiers,
raw xcodebuild logs, live VNC credentials, or helper paths. Set
`NARU_PHYSICAL_IOS_DEVICE_ID` only when multiple physical iPhones are connected,
and set `NARU_XCODE_DEVELOPMENT_TEAM` locally or through `launchctl` when
testing a specific signing team. If no team is supplied and exactly one local
Apple Development signing team is available, the runner may use it for the
build check while reporting only `developmentTeamStatus=inferred`.
`physical-team-inference-self-test` verifies the missing, ambiguous, inferred,
and explicit-environment branches without invoking `security` or `xcodebuild`.
`glance-scale-sweep` is a fixed short VNC/helper synthetic candidate sweep for
the benchmark-only first-frame visible-glance scales `0.45`, `0.35`, and
`0.25`. It rejects extra arguments to keep the candidate comparison repeatable.
`glance-025-duration-probe` is a fixed VNC-only poor-network probe for
`visible-glance` scale `0.25` plus `local-low-latency-rgb565`. It uses
environment/`launchctl` live credentials, rejects extra arguments, and runs a
12 second duration-only sustained phase against the
`iphone-poor-network-traffic-v1` target. If the live host or password is not
present in the current shell or `launchctl`, the mode fails before benchmarking
with the fixed missing-environment-variable setup message.
`glance-025-profile-sweep` uses the same fixed `0.25` poor-network shape as the
duration probe, but compares the current app-selectable stream profile
candidates. It rejects extra arguments and should be rerun before changing the
default stream profile for poor-network startup.

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
  --environment-preflight \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

To exercise the helper-video transport without requiring live VNC target
credentials, run the probe-only mode. This is the fastest gate after installing
or granting the helper because it reports only helper-video fixed labels and
does not connect to the VNC server.

```bash
NARU_HELPER_EXECUTABLE="$(launchctl getenv NARU_HELPER_EXECUTABLE)" \
swift run VNCLiveBenchmark \
  --helper-video-probe-only \
  --visual-transport helper-video \
  --helper-video-probe external-helper-synthetic-encoded-tcp \
  --json
```

After Screen Recording is granted to `NaruHelperDev`, rerun probe-only with the
real capture source before attempting the full constrained-cellular comparison:

```bash
NARU_HELPER_EXECUTABLE="$(launchctl getenv NARU_HELPER_EXECUTABLE)" \
swift run VNCLiveBenchmark \
  --helper-video-probe-only \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

For `external-helper-screen-capturekit-tcp`, the preflight emits schema `6`.
The benchmark process still does not use its own Screen Recording permission
state, but it now launches the selected helper executable with
`--video-capability` and records only fixed helper capability labels. A helper
app bundle missing Screen Recording permission reports
`helperVideoScreenCapturePermissionStatus=missing`,
`helperVideoExternalCapability.status=permissionMissing`, and setup action
`grant-helper-video-app-screen-recording-permission`. A SwiftPM helper artifact
uses setup action `install-stable-helper-video-executable`. If the helper
capability command does not return within the bounded timeout, the preflight
reports `helperVideoExternalCapability.status=timedOut`, issue code
`helper-video-external-helper-timed-out`, and setup action
`inspect-helper-video-capability`.

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
If the helper path was installed by
`scripts/install-naru-helper-dev-app.sh --set-launchctl-env`, pass it into
explicit benchmark shells with:

```bash
NARU_HELPER_EXECUTABLE="$(launchctl getenv NARU_HELPER_EXECUTABLE)" \
swift run VNCLiveBenchmark ...
```

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

## Implemented App-Side Helper Video Benchmark

```bash
swift test --filter HelperVideoAppRunnerBenchmarkTests

NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=1 \
swift test --filter HelperVideoAppRunnerBenchmarkTests

NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=1 \
NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES=2 \
swift test --filter HelperVideoAppRunnerBenchmarkTests/testNetworkBackedHelperVideoBootstrapThroughAppModelSmoke
```

The default command proves the benchmark target still skips during normal test
loops. The opt-in command measures finite helper-video H.264 access units
through app visual transport selection and CoreMedia sample-buffer creation.
On macOS SwiftPM runs, it also attempts an optional VideoToolbox synthetic
helper source and skips that case with a fixed label if the host encoder is not
available. The network-backed smoke command starts the helper-side TCP
`NWListener`, connects through `HelperVideoStreamNetworkClient` after the app
receives its first VNC framebuffer, feeds the iOS sample-buffer renderer, and
confirms VNC pointer/control remains active. Do not store payload bytes, display
dimensions, helper endpoints, byte counts, exact timings, raw encoder errors,
host names, or credentials in benchmark artifacts.

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
