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
```

`--video-capability` emits only fixed catalog labels such as
`permissionMissing`, `granted`, `notChecked`, `available`, or `unavailable`.
It must not emit display identifiers, dimensions, window names, endpoints,
host names, byte counts, frame content, or exact timings.

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

The helper-video side of the report is still a benchmark-only fake transport
shape until the helper stream implementation lands. Reports must preserve the
privacy boundary from `spec.md` and `research.md`.

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
