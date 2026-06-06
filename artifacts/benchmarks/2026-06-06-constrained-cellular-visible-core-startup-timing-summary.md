# Constrained-Cellular Visible-Core Startup Timing Summary - 2026-06-06

This increment extends the visible-core startup benchmark with first-frame
receive timing so slow startup can be separated into server/update wait,
payload read, and client processing without exposing frame contents.

## What Changed

- Bumped `VNCLiveBenchmark` reports to schema v59.
- Added `firstFrameReceiveTiming` to stream-shape profile probes.
- Added aggregate first-frame receive timing fields for total, network read,
  first-byte wait, payload read, client processing, and first-byte/payload
  network shares.
- Text reports now print first-frame receive timing for probes and aggregates.

The production app default remains unchanged. This is a benchmark/reporting
change only.

## Verification Commands

```sh
swift test --filter BenchmarkStreamShapeSummaryTests
swift run VNCLiveBenchmark --help | rg -n "schema v59|first-frame receive|visible-core"
swift run VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-constrained-cellular-visible-core-startup --json
```

## Live Result

Safe aggregate report fields:

- `schemaVersion`: 59
- `networkCondition`: `constrained-cellular`
- `streamShapeGatePreset`: `sustained-v2-constrained-cellular-visible-core-startup`
- `streamShapeFirstFrameRequestMode`: `visible-core`
- `firstFrameRequestAreaPermille`: 300 for every profile probe

Per-profile first-frame result:

| Profile | Startup | First-Byte | Payload Read | Client Processing | Gate Verdict | Primary Issue |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| `local-low-latency` | timeout | n/a | n/a | n/a | fail | `probe-failed` |
| `local-low-latency-rgb565` | 20.761 s | 0.962 s | 18.638 s | 1.161 s | fail | `first-frame-failed` |
| `zrle-compression-0` | timeout | n/a | n/a | n/a | fail | `probe-failed` |
| `zrle-compression-0-rgb565` | 20.766 s | 0.952 s | 18.681 s | 1.133 s | fail | `first-frame-failed` |

First-frame aggregate network split:

- `local-low-latency-rgb565`: first-byte 49 permille, payload 951 permille
- `zrle-compression-0-rgb565`: first-byte 48 permille, payload 952 permille

Sustained request/response aggregate health from the same run:

- `averageContentFramesPerSecond`: 1.86
- `averageUpdateMilliseconds`: 462
- `maxP95UpdateMilliseconds`: 631
- `averageFirstByteWaitSharePermille`: 1000
- `averagePayloadReadSharePermille`: 0
- `recommendedNextProbe`: `inspectUpdateWaitTiming`

## Interpretation

The visible-core startup failure is not mainly first-byte wait once RGB565
gets a first frame. The successful first frame spends roughly 95% of network
read time in payload read, so the next startup lever should reduce startup
payload pressure further: lower initial pixel depth, smaller startup region,
remote desktop resize, tighter/lossier encoding where supported, or a staged
startup that paints an even smaller useful area first.

The sustained stream still shows first-byte wait dominance after startup, so
steady-state smoothness needs a separate update-wait/cadence pass. Treat
startup payload pressure and sustained update-wait cadence as different
optimization tracks.

## Safety

The report and this artifact contain only fixed profile/preset/target/mode
labels, aggregate timing summaries, aggregate counts, aggregate permille ratios,
and fixed issue/triage labels. They do not contain host identity, credentials,
port values, proxy ports, upstream hosts, byte counts, framebuffer dimensions,
coordinates, pixels, cursor pixels, raw payloads, command text, command output,
draft text, marked text, or IME state.
