# Post-Inertia Viewport Live Benchmark Summary

Date: 2026-06-04

Purpose: capture a short redacted live VNC baseline after the viewport inertia
and compose-reset PR, before deferring direct gesture viewport-state publishing.
The run was against a private local VNC endpoint through `VNCLiveBenchmark` and
stores only aggregate schema-v22 metrics.

Safety: no host identity, password, framebuffer dimensions, coordinates, pixels,
cursor pixels, byte counts, raw payloads, or raw errors are recorded here.

Command shape:

```bash
NARU_LIVE_MAC_HOST=<redacted> swift run VNCLiveBenchmark \
  --json \
  --ask-password \
  --first-frame-profiles stream-shape-profiles \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-profiles local-low-latency,zrle-compression-0 \
  --stream-shape-transport request-response \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --timeout 5 \
  --idle-timeout 2
```

Key results:

| Profile | Actual encoding | Content FPS | Delivered FPS | Update avg/p95/max | Network avg/p95/max | Client avg/p95/max | Adaptive pressure |
| --- | --- | ---: | ---: | --- | --- | --- | ---: |
| local-low-latency | Raw only | 6.30 | 7.25 | 110 / 478 / 533 ms | 104 / 477 / 512 ms | 4 / 11 / 17 ms | 0 permille |
| zrle-compression-0 | ZRLE only | 5.35 | 6.45 | 119 / 482 / 503 ms | 107 / 481 / 491 ms | 11 / 95 / 170 ms | 310 permille |

Interpretation:

- The local-low-latency profile was recommended for this target because it had
  the lowest average request/response update latency.
- The default candidate was network/server-wait dominated rather than
  client-processing dominated: client p95 stayed under one display frame, while
  network/read p95 was about 477 ms.
- ZRLE was honored by the server, but its client-processing tail activated the
  app-style adaptive pressure pacing for 31 percent of received samples. That
  matches the hot-device symptom better than the Raw-only profile, but it also
  delivered slightly lower visible content FPS in this short local run.
- Renderer upload strategy was partial-upload only for content frames in both
  profiles, so this specific run did not point to full Metal texture uploads as
  the primary bottleneck.

Follow-up change:

- Direct pinch, zoomed pan, and pan deceleration now keep visible motion on the
  UIKit/Metal transform path and defer SwiftUI/PiP state mirroring until the
  gesture settles. Trackpad auto-pan keeps its existing display-link publish
  behavior because cursor mapping and model feedback are part of that hot path.
