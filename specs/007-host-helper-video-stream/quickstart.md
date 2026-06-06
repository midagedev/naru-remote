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
```

## Implemented App Model Tests

```bash
swift test --filter NaruRemoteAppModelTests/testModelSelectsHelperVideoVisualTransportForPairedReachableProfile
swift test --filter NaruRemoteAppModelTests/testHelperVideoStallFallsBackToVNCWithoutClearingComposeDraft
```

## Planned Helper Build

```bash
swift build --product NaruHelper
swift test --filter NaruHelperVideo
```

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
