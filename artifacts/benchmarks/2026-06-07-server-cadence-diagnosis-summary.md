# Server Cadence Diagnosis Summary

Date: 2026-06-07 KST

## Purpose

Add `streamShapeServerCadenceDiagnosis` to `VNCLiveBenchmark` schema v68 so
10fps VNC failures are classified by the dominant request/response bottleneck:
server first-byte wait, payload read, request loop, or local processing.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`
- Local fake RFB smoke JSON:
  `NARU_LIVE_MAC_HOST=127.0.0.1 NARU_LIVE_MAC_PORT=5901 NARU_LIVE_MAC_PASSWORD=<redacted> swift run --quiet VNCLiveBenchmark ... --json`
- `swift run --quiet VNCLiveBenchmark --help | rg "schema v68|server cadence|request/server cadence"`
- Live 10fps VNC probe:
  `scripts/run-naru-live-benchmark.sh glance-025-10fps-duration-probe`

## Fake Smoke Result

- Report schema: `68`
- `streamShapeServerCadenceDiagnosis`: present
- Status: `no-usable-samples`
- Recommended next action: `collectLongerRun`

The fake fixture serves only a deterministic first-frame transcript, so it is a
schema/serialization smoke check rather than a sustained performance result.

## Live 10fps Result

- Wrapper status: `passed`
- Report schema: `68`
- Benchmark decision: `fail`
- Target: `iphone-remote-desktop-10fps-v1`
- Profile: `local-low-latency-rgb565`
- Content FPS: `1.90`
- Average update: `525` ms
- P95 update: `920` ms
- First-byte wait p95: `630` ms
- Payload-read p95: `462` ms
- First-byte wait share: `918` permille
- Payload-read share: `82` permille
- Dominant phase: `network-read`
- Slow dominant phase: `network-read`
- Network-read subphase: `first-byte-wait`
- Slow network-read subphase: `first-byte-wait`
- Server cadence status: `first-byte-wait-dominated`
- Recommended next action: `inspectServerUpdateCadence`

## Interpretation

The VNC stream remains far below the 10fps product bar. The new diagnosis
routes the current VNC failure to server update cadence / first-byte timing
inspection, not to another profile-only promotion. Helper-video remains the
more plausible path for Chrome-Remote-like smoothness while VNC stays useful as
an input/control/fallback transport.

## Privacy

This artifact records only fixed labels, aggregate counts, aggregate
millisecond summaries, and permille shares. It omits host identity, credentials,
ports, helper paths, executable paths, command lines, raw stdout/stderr, raw
TCP/RFB errors, coordinates, dimensions, pixels, byte counts, stimulus command
text, draft text, marked text, IME state, keystroke content, and exact helper
timings.
