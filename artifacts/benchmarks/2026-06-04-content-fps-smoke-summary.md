# Content FPS Smoke Summary

Date: 2026-06-04 KST

Target: local private VNC endpoint, redacted by `VNCLiveBenchmark`

Configuration:

- Tool: `swift run VNCLiveBenchmark --ask-password`
- Code under test: schema-v15 content-frame FPS reporting
- Full-refresh samples: 0
- Stream-shape samples: 24
- Stream-shape profiles: `local-low-latency`
- Stream-shape transport: `request-response`
- Stream-shape empty backoff: `app`
- First-frame profiles: `none`
- Frame interval: 0.033 seconds
- Idle frame interval: 0.05 seconds
- Idle timeout: 0.75 seconds
- Schema: 15
- Safety: output omitted host, password, server name, framebuffer dimensions,
  pixel payloads, byte counts, cursor pixels, and raw error descriptions.

| Profile | Status | Samples | All-update FPS | Content FPS | Update avg/p50/p95 ms | Tail >=250ms / >=1000ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| local-low-latency | mixed-updates | 24 / 24 | 3.63 | 3.03 | 235 / 43 / 605 | 5 / 1 |

Additional aggregates:

- Empty/content/timeouts: 4 / 20 / 0
- Tail content/full-dirty/full-upload: 3 / 1 / 1
- Renderer partial/full uploads: 19 / 1
- ContinuousUpdates standalone probe: failed with
  `continuous-probe-receive-connection-failed`

Interpretation:

- Content-frame FPS separates visible update cadence from empty update polling.
  In this run, all-update FPS was 3.63 while content FPS was 3.03.
- Tail buckets still show one very-slow update and one slow full-dirty/full-upload
  frame, but multiple slow content frames were not full-upload classified.
- The next optimization should compare whether request pacing changes improve
  content FPS and tail counts, not only aggregate delivered update FPS.
