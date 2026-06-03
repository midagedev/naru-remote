# 2026-06-04 Profile Recommendation Benchmark Summary

Safety boundary: these notes preserve only aggregate benchmark outputs. They
omit host, password, server name, framebuffer dimensions, coordinates, pixels,
byte counts, cursor pixels, and raw error descriptions.

## Synthetic Renderer Check

Command:

```sh
NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests
```

Result:

- Full allocation + upload stayed in the low single-digit millisecond range.
- Steady full upload was roughly sub-millisecond.
- Small dirty-rectangle upload was tens of microseconds.
- Same-frame upload gating was effectively near-zero cost.

Takeaway: renderer full-upload avoidance is still valuable, but the live heat
and FPS problem is more likely to come from update-request pacing, encoding
choice, and server update shape than from the paused Metal view itself.

## Live localhost VNC, all-profile smoke

Command shape:

```sh
swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --stream-shape-samples 12 \
  --stream-shape-profiles all \
  --stream-shape-transport both \
  --continuous-update-samples 2 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Result:

- Request/response profiles connected and streamed.
- ContinuousUpdates failed in the receive phase for every tested profile.
- Request/response renderer uploads were partial-only in the short stream-shape
  probes.
- The fastest short request/response profile was `zrle-compression-0`, with
  lower average update latency and higher content FPS than the current
  `local-low-latency` profile in this run.

## Live localhost VNC, 20-second sustained normal pacing

Command shape:

```sh
swift run VNCLiveBenchmark \
  --attempts 1 \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-profiles local-low-latency,zrle-compression-0 \
  --stream-shape-transport request-response \
  --continuous-update-samples 1 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Profile comparison:

| Profile | Content FPS | Update avg / p95 ms | Renderer full uploads | Slow samples |
| --- | ---: | ---: | ---: | ---: |
| `local-low-latency` | 4.80 | 150 / 475 | 21 permille | 17 / 113 |
| `zrle-compression-0` | 6.10 | 112 / 478 | 0 permille | 20 / 142 |

Takeaway: `zrle-compression-0` is the stronger normal-pacing candidate on this
run. It avoided full uploads and improved average update latency/content FPS,
while p95 latency remained similar.

## Live localhost VNC, 20-second sustained low-power pacing

Command shape:

```sh
swift run VNCLiveBenchmark \
  --attempts 1 \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-profiles local-low-latency,zrle-compression-0 \
  --stream-shape-transport request-response \
  --stream-shape-power-mode low-power \
  --continuous-update-samples 1 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Profile comparison:

| Profile | Content FPS | Update avg / p95 ms | Renderer full uploads | Slow samples |
| --- | ---: | ---: | ---: | ---: |
| `local-low-latency` | 4.15 | 141 / 499 | 0 permille | 17 / 100 |
| `zrle-compression-0` | 4.40 | 146 / 488 | 0 permille | 19 / 100 |

Takeaway: under low-power pacing, the two profiles are close. This is not enough
evidence to switch production defaults by itself, but it is enough to make the
benchmark report recommend the best measured request/response profile
explicitly so future longer physical-device runs do not require manual JSON
comparison.

## Schema v18 smoke

After implementing the recommendation field, a short 3-sample live run emitted
`schemaVersion: 18` and a `streamShapeRecommendation` object. The recommendation
again selected `zrle-compression-0` for this target based on lower aggregate
request/response update latency.
