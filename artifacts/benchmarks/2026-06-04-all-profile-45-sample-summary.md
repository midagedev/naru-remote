# All-Profile Stream-Shape 45-Sample Summary

Date: 2026-06-04 KST

Target: local private VNC endpoint, redacted by `VNCLiveBenchmark`

Configuration:

- Tool: `swift run VNCLiveBenchmark --ask-password`
- Full-refresh samples: 0
- Stream-shape samples: 45
- Stream-shape transport: `request-response`
- Stream-shape empty backoff: `app`
- First-frame profiles: `none`
- Frame interval: 0.033 seconds
- Idle frame interval: 0.05 seconds
- Idle timeout: 0.75 seconds
- Schema: 12 (captured before this PR's targeted-profile CLI change bumped
  benchmark output to schema 13)
- Safety: output omitted host, password, server name, framebuffer dimensions,
  pixel payloads, byte counts, cursor pixels, and raw error descriptions.

| Profile | Status | Samples | Delivered FPS | Update avg/p50/p95 ms | Empty/content/timeouts | Renderer partial/full |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| local-low-latency | failed (`stream-connect-read-timeout`) | 0 / 45 | n/a | n/a | 0 / 0 / 0 | 0 / 0 |
| tight-first | mixed-updates | 45 / 45 | 6.10 | 124 / 37 / 458 | 6 / 39 / 0 | 39 / 0 |
| zrle-first | mixed-updates | 45 / 45 | 5.38 | 145 / 38 / 499 | 7 / 38 / 0 | 38 / 0 |
| zrle-compression-0 | mixed-updates | 45 / 45 | 6.39 | 115 / 32 / 465 | 10 / 35 / 0 | 35 / 0 |
| adaptive-good-zrle | mixed-updates | 45 / 45 | 5.44 | 143 / 38 / 494 | 7 / 38 / 0 | 38 / 0 |
| adaptive-poor-zrle | mixed-updates | 45 / 45 | 5.23 | 150 / 42 / 503 | 6 / 39 / 0 | 39 / 0 |
| adaptive-good-full | mixed-updates | 45 / 45 | 5.75 | 132 / 33 / 467 | 10 / 35 / 0 | 35 / 0 |
| adaptive-poor-full | mixed-updates | 45 / 45 | 5.67 | 136 / 41 / 498 | 7 / 38 / 0 | 38 / 0 |

ContinuousUpdates standalone probe:

- Status: failed
- Failure label: `continuous-probe-receive-connection-failed`

Interpretation:

- This run does not justify enabling ContinuousUpdates by default.
- `local-low-latency` failed at stream connect in this run despite succeeding in
  earlier shorter runs; treat it as a candidate that needs repeated targeted
  validation rather than as a settled loser.
- `zrle-compression-0`, `tight-first`, and `adaptive-good-full` are the best
  next targeted long-run candidates from this snapshot.
- All successful profiles reported partial renderer uploads only, so the
  current bottleneck is more likely request/response latency, server encoding
  choice, CPU decode, or remote repaint cadence than full-texture upload.
