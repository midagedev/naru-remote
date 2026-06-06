# Constrained-Cellular Sustained Traffic Wait Gate

Date: 2026-06-06

Purpose: verify schema v61 poor-network traffic gates separate sustained
payload-read pressure from first-byte/update-wait pressure after the
visible-focus startup traffic reduction.

Command shape:

```bash
NARU_LIVE_MAC_HOST=<redacted> \
NARU_LIVE_MAC_PORT=5900 \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --ask-password \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-visible-focus-startup \
  --json
```

Safety: the report used schema v61 and kept target, credential, proxy, byte
count, framebuffer dimension, coordinate, pixel, cursor-pixel, raw payload,
command output, draft text, marked text, and IME state values out of the
artifact.

## Result

- Overall decision: `fail`.
- Network condition: `constrained-cellular`.
- First-frame request mode: `visible-focus`.
- First-frame request area: 192 permille.
- Sustained request area: 364 permille.
- Full-color candidates:
  - `local-low-latency`: `stream-first-frame-read-timeout`.
  - `zrle-compression-0`: `stream-first-frame-read-timeout`.
- Usable RGB565 candidates:
  - `local-low-latency-rgb565`: startup about 16.3 s, average update about
    513 ms, max p95 update about 646 ms, content FPS about 1.95.
  - `zrle-compression-0-rgb565`: startup about 16.3 s, average update about
    505 ms, max p95 update about 610 ms, content FPS about 1.98.
- Order-neutral recommendation: `zrle-compression-0-rgb565`.
- Request cadence health: high content hit, p95 warning, recommended next
  probe `inspectUpdateWaitTiming`.

## Traffic Interpretation

- Startup is still payload-read dominated for RGB565 first frames:
  first-frame network read split was roughly 60-61 permille first-byte wait and
  939-940 permille payload read.
- Sustained streaming is no longer payload-read dominated in the measured
  samples: sustained payload-read share was 0 permille and first-byte wait
  share was 1000 permille for the usable RGB565 profiles.
- Schema v61 therefore classified the usable RGB565 gates with
  `first-byte-wait-warning`, alongside content FPS / average update / p95
  warnings. It did not classify sustained `payload-read-warning` or
  `payload-read-failed`.

## Next Unit

Keep production defaults unchanged. The next large unit should inspect
request/update wait timing and request-response cadence. Startup traffic work
can continue separately as a staged first-useful-paint candidate, but it should
not be promoted until the sustained poor-network gate and physical iPhone gate
both pass.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`
- `swift run VNCLiveBenchmark --help | rg -n "schema v61|payload-read|first-byte|visible-focus-startup"`
- Live schema v61 constrained-cellular visible-focus run with the command shape
  above.
