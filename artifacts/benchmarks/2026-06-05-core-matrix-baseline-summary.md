# 2026-06-05 Core Matrix Baseline Summary

## Trigger

After schema v31 split ZRLE inflate from tile/apply timing, the first live run
showed local decode was not the p95 bottleneck. The next larger unit needs a
repeatable baseline that compares request cadence, transport, and encoding
profiles before changing production defaults.

## Baseline Target

Keep `iphone-practical-baseline-v1` as the practical floor:

- content FPS should be at least 8 to pass, below 4 fails
- p95 update latency should be at most 500 ms to pass, above 1000 ms fails
- client-processing p95 should be at most 24 ms to pass, above 50 ms fails
- renderer full-upload pressure should be at most 50 permille to pass
- adaptive client-pressure pacing should be at most 100 permille to pass

The new `core-matrix` profile selection is the standard first pass for larger
optimization PRs. It runs:

- `local-low-latency` — current app default
- `zrle-compression-0` — ZRLE compression-level candidate without cursor or
  clipboard pseudo-encoding isolation
- `tight-first` — non-ZRLE candidate that exposes server fallback behavior
- `adaptive-good-full` — future adaptive/full-capability candidate

Pair `core-matrix` with `--stream-shape-transport both` when deciding whether
the next large unit should target request/response cadence, ContinuousUpdates,
encoding profile, local decode, renderer uploads, or server compatibility.

## Sources Rechecked

- RFC 6143, RFB protocol: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

Relevant takeaways:

- RFB update flow is client-request driven unless an extension such as
  ContinuousUpdates changes the stream model, so transport and request cadence
  need direct measurement.
- Mature VNC viewers expose preferred encoding, compression, quality, and
  related transport controls, which argues for a measured candidate matrix
  rather than changing Naru's default encoding order from one run.

## Live Benchmark

Command shape:

```bash
swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 8 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --first-frame-profiles stream-shape-profiles \
  --stream-shape-profiles core-matrix \
  --stream-shape-transport both \
  --continuous-update-samples 1 \
  --timeout 6 \
  --idle-timeout 1 \
  --ask-password \
  --json
```

Safe top-level settings:

- schema: 31
- stream-shape profiles: `core-matrix`
- transports: `both`
- duration: 8 seconds per probe
- content interval: 16.7 ms
- idle interval: 50 ms
- client-pressure parity: `app`
- viewport-interaction parity: `app`

First-frame sweep:

| profile | first frame |
| --- | ---: |
| `local-low-latency` | 4548 ms |
| `zrle-compression-0` | 3496 ms |
| `tight-first` | 3006 ms |
| `adaptive-good-full` | 3474 ms |

Stream-shape matrix:

| profile | transport | status | verdict | issue | samples | content FPS | update p50/p95 | network p95 | client p95 | ZRLE tile p95 | full upload | slow/very slow | actual encoding |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `local-low-latency` | request-response | mixed | fail | `content-fps-failed` | 16/15 | 1.87 | 156/372 ms | 365 ms | 10 ms | 10 ms | 0 permille | 8/0 | ZRLE |
| `zrle-compression-0` | request-response | mixed | fail | `content-fps-failed` | 16/15 | 1.87 | 151/412 ms | 403 ms | 15 ms | 10 ms | 0 permille | 8/0 | ZRLE |
| `tight-first` | request-response | mixed | fail | `content-fps-failed` | 16/14 | 1.75 | 198/382 ms | 374 ms | 9 ms | n/a | 0 permille | 8/0 | Raw |
| `adaptive-good-full` | request-response | failed | fail | `stream-connect-read-timeout` | 0/0 | 0.00 | n/a | n/a | n/a | n/a | n/a | 0/0 | n/a |
| `local-low-latency` | continuous-updates | failed | fail | `stream-continuous-updates-connection-failed` | 0/0 | 0.00 | n/a | n/a | n/a | n/a | n/a | 0/0 | n/a |
| `zrle-compression-0` | continuous-updates | failed | fail | `stream-continuous-updates-connection-failed` | 0/0 | 0.00 | n/a | n/a | n/a | n/a | n/a | 0/0 | n/a |
| `tight-first` | continuous-updates | failed | fail | `stream-continuous-updates-connection-failed` | 0/0 | 0.00 | n/a | n/a | n/a | n/a | n/a | 0/0 | n/a |
| `adaptive-good-full` | continuous-updates | failed | fail | `stream-continuous-updates-connection-failed` | 0/0 | 0.00 | n/a | n/a | n/a | n/a | n/a | 0/0 | n/a |

Standalone ContinuousUpdates probe:

- status: `failed`
- safe failure label: `continuous-probe-receive-connection-failed`

Recommendation:

- selected profile: `local-low-latency`
- transport: request-response
- reason: lowest average update latency among successful request/response
  profiles
- caveat: all successful request/response profiles still failed the practical
  baseline on content FPS

## Interpretation

- On this macOS Screen Sharing target, ContinuousUpdates remains unusable; every
  matrix ContinuousUpdates stream failed before producing samples.
- The successful request/response probes are dominated by receive/network wait,
  not local decode or renderer upload. Client-processing p95 stayed between
  9 and 15 ms and full-upload pressure stayed at 0 permille, while network-read
  p95 stayed around 365 to 403 ms.
- `local-low-latency` and `zrle-compression-0` both negotiated actual ZRLE and
  had similar content FPS. The current app default should remain unchanged until
  a physical iPhone run or a controlled dynamic-content run shows a different
  winner.
- `tight-first` negotiated Raw on this target, which keeps it valuable as a
  server-fallback comparison but not as the default path for this local Screen
  Sharing baseline.
- `adaptive-good-full` succeeded in the first-frame sweep but timed out on the
  request/response stream-shape connect, so the next compatibility unit should
  isolate which advertised extension or hint causes that stream failure.

## Next Larger Units

- Add a controlled dynamic-content stimulus for live benchmarks so content FPS
  is measured against repeatable screen activity rather than incidental desktop
  motion.
- Keep ContinuousUpdates off by default and isolate the failure phase with a
  smaller extension-probe matrix before attempting production use.
- Run the same `core-matrix` shape on a physical iPhone after the stimulus work
  so thermal/FPS and finger-to-glass smoothness have a comparable baseline.

## Verification

- `swift test --filter BenchmarkStreamShapeProfileSelectionTests`
  - Result: passed, 10 tests, 0 failures.
- Live `VNCLiveBenchmark` `core-matrix` run
  - Result: command succeeded, request/response probes completed for three
    profiles, ContinuousUpdates probes failed with safe catalog labels.

## Privacy Rule

This artifact records only fixed profile labels, fixed transport labels,
aggregate timing summaries, aggregate FPS, aggregate renderer/upload counts,
safe failure labels, and practical verdict codes. It does not store host
identity, credentials, framebuffer dimensions, rectangle coordinates, pixels,
cursor pixels, byte counts, raw samples, raw payloads, or raw error text.
