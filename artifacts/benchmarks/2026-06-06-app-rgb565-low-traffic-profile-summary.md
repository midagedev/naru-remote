# App RGB565 Low-Traffic Stream Profile Summary

Date: 2026-06-06

## Change

This increment wires the benchmark-backed `zrle-compression-0-rgb565` stream
profile into the app-side stream profile experiment. The profile keeps ZRLE at
compression level 0 and applies the RGB565-in-32-bit pixel format before the
first streaming framebuffer request, so poor-network traffic experiments can
be reproduced from the app without changing production defaults.

The default app stream remains unchanged. The new profile is opt-in through the
existing stream profile toggle.

## Verification

Unit tests:

```sh
swift test --filter AppSettingsCodableTests
swift test --filter NaruRemoteAppModelTests/testModelBuildsRGB565LowTrafficStreamConnectorOnConnect \
  --filter NaruRemoteAppModelTests/testModelLetsPowerSaverOverrideRGB565LowTrafficStreamConnectorOnConnect \
  --filter NaruRemoteAppModelTests/testModelRenegotiatesConfiguredZrleStreamEncodingOnConnect \
  --filter NaruRemoteAppModelTests/testModelPersistsStreamEncodingModeToggle
swift test --filter BenchmarkStreamShapeProfileSelectionTests/testPixelFormatIsolationIncludesAppLowTrafficStreamEncodingLabel \
  --filter BenchmarkStreamShapeProfileSelectionTests/testPixelFormatIsolationSelectsFullColorAndRGB565Pairs \
  --filter BenchmarkStreamShapeSummaryTests/testPoorNetworkTrafficTargetFailsPayloadReadPressure
swift test
```

Result: all passed. The full package run executed 952 tests with 10 skips and
0 failures.

Live smoke:

```sh
NARU_LIVE_MAC_HOST=<redacted> \
NARU_LIVE_STIMULUS_COMMAND=<redacted> \
swift run VNCLiveBenchmark --ask-password \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-visible-focus-startup \
  --stream-shape-samples 4 \
  --stream-shape-duration-seconds 5 \
  --stream-shape-profile-iterations 1 \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --json
```

Safe aggregate result:

- Schema: v61
- Network condition: `constrained-cellular`
- First-frame request mode: `visible-focus`
- Practical target: `iphone-poor-network-traffic-v1`
- Overall verdict: `fail`
- Primary issue: `probe-failed`
- Recommended next probe: `inspectServerTransportCadence`
- Full-color profiles (`local-low-latency`, `zrle-compression-0`) failed first
  frame with the fixed safe label `stream-first-frame-read-timeout`.
- RGB565 profiles survived startup and reached all 4 requested sustained
  samples, but remained warning-only because sustained updates were
  first-byte-wait dominated.
- `local-low-latency-rgb565`: warning, about 2.49 content FPS, average update
  about 401 ms, p95 update about 606 ms, first-byte wait p95 about 598 ms,
  payload-read p95 0 ms.
- `zrle-compression-0-rgb565`: warning, about 1.95 content FPS, average update
  about 514 ms, p95 update about 635 ms, first-byte wait p95 about 630 ms,
  payload-read p95 about 1 ms.

## Interpretation

The app-side RGB565 low-traffic profile now matches the poor-network benchmark
candidate label and applies early enough to affect the first streamed frame.
The live run reinforces the current split:

- Startup under constrained cellular is traffic/payload sensitive; full-color
  profiles still fail first-frame startup.
- Sustained visible-region streaming is no longer payload-read dominated for
  RGB565 candidates; it is first-byte-wait/update-cadence dominated.

Next work should inspect update-wait timing and request cadence before changing
production defaults. The app profile is useful now as an explicit poor-network
experiment toggle for physical-device runs.

## Privacy

This artifact records only fixed labels, aggregate timing summaries, aggregate
FPS, and safe verdict/issue labels. It omits host identity, credentials, ports,
framebuffer dimensions, coordinates, pixels, byte counts, raw payloads, raw
errors, stimulus command text, command output, draft text, marked text, and IME
state.
