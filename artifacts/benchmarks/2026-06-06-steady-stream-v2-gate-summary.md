# 2026-06-06 Steady Stream Sustained v2 Gate

Target: `iphone-sustained-usability-v2`

## Purpose

The sustained v2 content-FPS target is 8fps against a 12Hz controlled stimulus.
The app's active viewport-interaction pacing floor is intentionally much lower
so pinch/pan and trackpad movement keep local touch handling smooth. Keeping
that interaction pacing enabled inside the same preset made the benchmark gate
ask for an 8fps stream while also applying a 4Hz-class interaction floor.

This increment separates those concerns:

- sustained v2 benchmark presets measure steady stream cadence
- active viewport-interaction smoothness remains a physical iPhone gate and a
  custom benchmark mode

## Implementation

- `sustained-v2-core`, `sustained-v2-request-response`, and
  `sustained-v2-pixel-format` now set
  `streamShapeViewportInteractionMode` to `off`.
- The presets still use app client-pressure pacing, app empty-backoff pacing,
  10 second duration, zero hidden preflight frames, 12Hz stimulus cadence, and
  the `iphone-sustained-usability-v2` target.
- Custom active-interaction stream experiments can still use
  `--stream-shape-viewport-interaction app` without a gate preset.
- Production app defaults are unchanged.

## Promotion Rule

Benchmark-green for stream defaults now means the steady-stream gate passes
first. Production default promotion still also requires the 10 minute physical
iPhone hand-feel, thermal, viewport, and Compose pass.

## Verification

- `swift test`
- Redacted live `sustained-v2-request-response` run:
  - `schemaVersion`: 44
  - `streamShapeViewportInteractionMode`: `off`
  - `streamShapeStimulusExpectedFramesPerSecond`: 12
  - `continuousUpdatesProbe.status`: `not-tested`
  - `streamShapeTransportCadenceDiagnosis.recommendedNextAction`:
    `compareRequestResponseEncodingProfiles`
  - `streamShapeOptimizationDecision.recommendedNextProbe`:
    `compareEncodingProfileGate`
  - order-neutral request/response recommendation:
    `zrle-compression-0`

Safe aggregate profile result:

| profile | verdict | main issues | avg content FPS | avg update | max p95 update | max client p95 | full upload |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | fail | client-processing-failed, very-slow-update | 6.06 | 116 ms | 488 ms | 154 ms | 0 permille |
| `zrle-compression-0` | warning | content-fps-warning, p95-update-warning | 6.34 | 108 ms | 482 ms | 13 ms | 0 permille |
| `tight-first` | fail | client-processing-failed, p95-update-failed | 5.92 | 114 ms | 510 ms | 131 ms | 0 permille |
| `adaptive-good-full` | fail | client-processing-failed, adaptive-pressure-failed | 5.89 | 117 ms | 494 ms | 148 ms | 0 permille |

The steady-stream split removed the impossible 4Hz interaction cap from the
8fps target. The best request/response candidate is still not benchmark-green,
but the next unit is now narrower: compare the default `local-low-latency`
profile against pure `zrle-compression-0` and reduce client-decode/tail pressure
before any production default promotion.

## Safe Reporting

This artifact records only fixed target, preset, and mode labels. It does not
store host identity, credentials, port values, raw TCP/RFB errors, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw payloads, raw
FPS, raw timings, stimulus command text, command output, draft text, marked
text, IME state, or full diagnostic payloads.
