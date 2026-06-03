# Selected-Profile Live Benchmark Smoke

Date: 2026-06-03 KST

Target: local macOS Screen Sharing over `localhost:5900`

Configuration:

- Attempts per first-frame profile: 1
- Full-refresh samples per successful attempt: 0
- First-frame profile selection: `stream-shape-profiles`
- Stream-shape profile selection: `local-low-latency`
- Stream-shape samples: 6
- Stream-shape frame interval: 0.033 seconds
- Continuous-update samples: 1
- Timeout: 5 seconds
- Idle timeout: 0.75 seconds
- Tool: `swift run VNCLiveBenchmark --ask-password`

Safety:

- Host, password, server name, framebuffer dimensions, pixels, byte counts,
  cursor pixels, and raw errors were not emitted.
- The report used `target: configured-redacted`.

Results:

| Probe | Result |
| --- | --- |
| First-frame sweep profiles | `local-low-latency` only |
| First-frame latency | 4,058 ms |
| Idle incremental probe | empty update in 10 ms |
| Stream-shape status | mixed-updates, 6/6 samples |
| Delivered incremental FPS | 2.05 |
| Update latency avg / p50 / p95 | 450 ms / 50 ms / 2,084 ms |
| Empty / content / timeout samples | 2 / 4 / 0 |
| Dirty rect count avg / p50 / p95 | 1 / 1 / 1 |
| Dirty area permille avg / p50 / p95 | 167 / 1 / 1,000 |
| Changed pixels permille avg / p50 / p95 | 0 / 1 / 1 |
| ContinuousUpdates | failed with safe `connection-failed` label |

Interpretation:

- `--first-frame-profiles stream-shape-profiles` avoided the all-profile
  first-frame sweep and made a short sustained-stream probe cheaper to run.
- The stream-shape sample still saw one full-screen dirty-area outlier
  (`p95=1000` permille). That matches the current optimization strategy:
  keep dirty-rectangle telemetry visible and defer encoding/default changes
  until longer physical iPhone runs show whether these outliers are common.
- ContinuousUpdates remains unsuitable as a default for macOS Screen Sharing.
