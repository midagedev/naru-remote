# Stream-Shape Profile Comparison: Live macOS VNC

Date: 2026-06-03 KST

Target: local macOS Screen Sharing over `localhost:5900`

Configuration:

- Attempts per profile: 1
- Full-refresh samples per successful attempt: 0
- Stream-shape samples per selected profile: 2
- Stream-shape profile selection: `all`
- Stream-shape frame interval: 0.033 seconds
- Continuous-update samples: 1
- Timeout: 5 seconds
- Idle timeout: 0.75 seconds
- Tool: `swift run VNCLiveBenchmark --json --ask-password`
- Report schema: 7

First-Frame Results:

| Profile | First-frame |
| --- | ---: |
| local-low-latency | 3,742 ms |
| tight-first | 2,975 ms |
| zrle-first | 3,263 ms |
| zrle-compression-0 | 3,304 ms |
| adaptive-good-zrle | 3,270 ms |
| adaptive-poor-zrle | 3,266 ms |
| adaptive-good-full | 3,332 ms |
| adaptive-poor-full | 3,289 ms |

Stream-Shape Results:

| Profile | FPS | Update avg | p50 | p95 | Empty / Content / Timeout |
| --- | ---: | ---: | ---: | ---: | --- |
| local-low-latency | 10.10 | 60 ms | 51 ms | 70 ms | 1 / 1 / 0 |
| tight-first | 8.89 | 75 ms | 9 ms | 141 ms | 1 / 1 / 0 |
| zrle-first | 4.91 | 168 ms | 43 ms | 294 ms | 1 / 1 / 0 |
| zrle-compression-0 | 13.51 | 38 ms | 22 ms | 54 ms | 1 / 1 / 0 |
| adaptive-good-zrle | 3.04 | 291 ms | 209 ms | 373 ms | 0 / 2 / 0 |
| adaptive-poor-zrle | 3.45 | 250 ms | 30 ms | 471 ms | 1 / 1 / 0 |
| adaptive-good-full | 9.17 | 73 ms | 22 ms | 125 ms | 1 / 1 / 0 |
| adaptive-poor-full | 4.48 | 186 ms | 52 ms | 321 ms | 0 / 2 / 0 |

Other Probes:

- Idle incremental probe: empty update in 329 ms.
- Continuous updates probe: failed with safe `connection-failed` label.

Interpretation:

- This short run is not enough to change app defaults, but schema-v7 now exposes
  the missing comparison: sustained incremental update shape across every
  encoding profile.
- `zrle-compression-0` looked promising for tiny incremental traffic in this
  sample, while the adaptive ZRLE profiles were slower. A longer physical
  iPhone run should repeat this with more samples before any default profile
  change.
- ContinuousUpdates remains a compatibility risk on macOS Screen Sharing.
