# Stream-Shape Profile Comparison: 8-Sample Live macOS VNC

Date: 2026-06-03 KST

Target: local macOS Screen Sharing over `localhost:5900`

Configuration:

- Attempts per profile: 1
- Full-refresh samples per successful attempt: 0
- Stream-shape samples per selected profile: 8
- Stream-shape profile selection: `all`
- Stream-shape frame interval: 0.033 seconds
- Continuous-update samples: 1
- Timeout: 5 seconds
- Idle timeout: 0.75 seconds
- Tool: `swift run VNCLiveBenchmark --ask-password`

First-Frame Results:

| Profile | First-frame |
| --- | ---: |
| local-low-latency | 4,454 ms |
| tight-first | 3,002 ms |
| zrle-first | 3,273 ms |
| zrle-compression-0 | 3,279 ms |
| adaptive-good-zrle | 3,323 ms |
| adaptive-poor-zrle | 3,283 ms |
| adaptive-good-full | 3,280 ms |
| adaptive-poor-full | 3,266 ms |

Stream-Shape Results:

| Profile | Status | FPS | Update avg | p50 | p95 | Empty / Content / Timeout |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| local-low-latency | failed | n/a | n/a | n/a | n/a | n/a |
| tight-first | mixed-updates | 5.64 | 139 ms | 43 ms | 454 ms | 1 / 7 / 0 |
| zrle-first | mixed-updates | 7.07 | 104 ms | 34 ms | 461 ms | 3 / 5 / 0 |
| zrle-compression-0 | mixed-updates | 5.56 | 143 ms | 32 ms | 437 ms | 3 / 5 / 0 |
| adaptive-good-zrle | mixed-updates | 6.83 | 110 ms | 39 ms | 468 ms | 3 / 5 / 0 |
| adaptive-poor-zrle | mixed-updates | 5.68 | 139 ms | 46 ms | 455 ms | 3 / 5 / 0 |
| adaptive-good-full | mixed-updates | 6.96 | 106 ms | 28 ms | 454 ms | 3 / 5 / 0 |
| adaptive-poor-full | mixed-updates | 5.65 | 134 ms | 31 ms | 465 ms | 3 / 5 / 0 |

Follow-Up Local-Low-Latency Check:

- Same configuration but `--stream-shape-profiles local-low-latency`.
- Stream-shape status: mixed-updates, 8/8 samples received.
- Delivered incremental FPS: 6.37.
- Update latency: avg 115 ms, p50 28 ms, p95 489 ms.
- Empty/content/timeouts: 1 / 7 / 0.

Other Probes:

- Idle incremental probe: empty update in 166 ms on the all-profile run.
- Continuous updates probe: failed with safe `connection-failed` label.

Interpretation:

- The 2-sample run that made `zrle-compression-0` look strongest did not repeat
  at 8 samples; `zrle-first`, `adaptive-good-zrle`, and `adaptive-good-full`
  were closer to the front on this run.
- `local-low-latency` had a transient stream-shape failure in the all-profile
  run but succeeded on an immediate local-only follow-up. This makes failure
  taxonomy important before changing defaults.
- ContinuousUpdates remains unsafe as a default on macOS Screen Sharing.
