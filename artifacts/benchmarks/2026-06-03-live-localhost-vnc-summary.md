# Live macOS VNC Benchmark

Date: 2026-06-03 KST

Target: local macOS Screen Sharing over `localhost:5900`

Configuration:

- Attempts per profile: 2
- Full-refresh samples per successful attempt: 1
- Continuous-update samples: 2
- Timeout: 5 seconds
- Idle timeout: 0.75 seconds
- Tool: `swift run VNCLiveBenchmark`

Results:

| Profile | First-frame avg | Full-refresh avg | Status |
| --- | ---: | ---: | --- |
| local-low-latency | 3,585 ms | 2,073 ms | 2/2 succeeded |
| tight-first | 2,975 ms | 2,068 ms | 2/2 succeeded |
| zrle-first | 3,307 ms | 2,413 ms | 2/2 succeeded |
| zrle-compression-0 | 3,306 ms | 2,396 ms | 2/2 succeeded |
| adaptive-good-zrle | 3,336 ms | 2,391 ms | 2/2 succeeded |
| adaptive-poor-zrle | 3,363 ms | 2,388 ms | 2/2 succeeded |
| adaptive-good-full | 3,317 ms | 2,392 ms | 2/2 succeeded |
| adaptive-poor-full | 3,314 ms | 2,397 ms | 2/2 succeeded |

Other probes:

- Idle incremental probe: empty update in 26 ms.
- Continuous updates probe: failed with a safe `connection-failed` label.

Interpretation:

- macOS Screen Sharing over localhost is not making full refreshes cheap;
  full refresh remains around 2 seconds in this short run.
- The empty incremental probe is fast, which means request cadence can
  become the client-side heat lever during active sessions.
- ContinuousUpdates needs a separate compatibility pass before it should
  be treated as a reliable pacing mechanism on macOS Screen Sharing.
- `tight-first` had the lowest first-frame average in this run, but the
  sample size is too small to change the default encoding profile without
  additional device/live-server runs.
