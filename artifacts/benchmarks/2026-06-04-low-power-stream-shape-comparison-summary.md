# Low Power Stream-Shape Pacing Comparison

Date: 2026-06-04 KST

Purpose: verify `VNCLiveBenchmark` schema v16 can mirror the app's normal vs
Low Power Mode stream pacing for sustained VNC request/response probes. This
artifact stores only redacted aggregate benchmark output. It does not include
target identity, framebuffer dimensions, coordinates, pixels, cursor pixels,
byte counts, raw payloads, raw errors, or credentials.

## Command Shape

All runs used:

- `VNCLiveBenchmark`
- schema v16
- `--first-frame-profiles none`
- `--stream-shape-profiles local-low-latency`
- `--stream-shape-transport request-response`
- `--stream-shape-samples 36`
- `--stream-shape-frame-interval 0.0166667`
- `--stream-shape-idle-frame-interval 0.05`
- `--stream-shape-empty-backoff app`
- `--continuous-update-samples 1`

Only `--stream-shape-power-mode` varied.

## Results

| Power mode | All-update FPS | Content-frame FPS | Received | Content | Empty | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms | Slow content | Full uploads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| normal | 5.49 | 4.73 | 36 | 31 | 5 | 157 | 25 | 485 | 5 | 1 | 1 | 1 |
| low-power | 4.91 | 4.50 | 36 | 33 | 3 | 156 | 42 | 505 | 7 | 0 | 6 | 0 |

Schema v16 also records the fixed app parity floors:

- content floor in low-power mode: `0.03333333333333333 s`
- idle floor in low-power mode: `0.125 s`

## Interpretation

The low-power profile reduced all-update cadence while preserving a similar
content-frame cadence in this short localhost/macOS Screen Sharing run. The
tail mix changed, so these numbers are not enough to claim physical-iPhone heat
comfort. They do prove the benchmark can now reproduce the app's Low Power Mode
pacing policy and compare it against normal mode with the same redacted summary
shape used by the rest of the VNC tuning work.

Residual risk:

- A physical iPhone sustained-session pass is still required before claiming
  reduced heat or battery impact.
