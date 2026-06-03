# Thermal Pacing Baseline: Live macOS VNC

Date: 2026-06-03 KST

Target: local macOS Screen Sharing over `localhost:5900`

Configuration:

- Attempts per profile: 1
- Full-refresh samples per successful attempt: 0
- Stream-shape samples: 5
- Stream-shape frame interval: 0.033 seconds
- Continuous-update samples: 1
- Timeout: 5 seconds
- Idle timeout: 0.75 seconds
- Tool: `swift run VNCLiveBenchmark --json --ask-password`

Results:

- All 8 encoding profiles completed first-frame connection.
- First-frame range across profiles: 3,049-3,927 ms.
- Idle incremental probe: empty update in 18 ms.
- Stream-shape probe: mixed updates, 5/5 samples received.
- Stream-shape delivered FPS: 6.76.
- Stream-shape update latency: avg 110 ms, p50 35 ms, p95 448 ms.
- Stream-shape empty/content/timeouts: 2 / 3 / 0.
- Dirty rectangles: average 1, max 1.
- Dirty area: average 1 permille, max 1 permille.
- Changed pixels: average 0 permille, max 1 permille.
- Continuous updates probe: failed with safe `connection-failed` label.

Interpretation:

- Nominal localhost behavior remains consistent with the existing 30 fps
  request cap: the app should not add extra pacing unless iOS reports elevated
  thermal pressure.
- The stream-shape result is mostly tiny dirty-rect traffic. That makes
  request cadence a practical heat lever: when the device reports fair,
  serious, or critical thermal pressure, reducing request frequency should cut
  client/network wakeups without changing protocol negotiation.
- ContinuousUpdates is still not reliable enough on macOS Screen Sharing to
  become the primary pacing mechanism.
