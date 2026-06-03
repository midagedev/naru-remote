# Stream-Shape Tail Bucket Smoke Summary

Date: 2026-06-04 KST

Target: local private VNC endpoint, redacted by `VNCLiveBenchmark`

Configuration:

- Tool: `swift run VNCLiveBenchmark --ask-password`
- Code under test: schema-v14 stream-shape tail buckets
- Full-refresh samples: 0
- Stream-shape samples: 36
- Stream-shape profiles: `local-low-latency`
- Stream-shape transport: `request-response`
- Stream-shape empty backoff: `app`
- First-frame profiles: `none`
- Frame interval: 0.033 seconds
- Idle frame interval: 0.05 seconds
- Idle timeout: 0.75 seconds
- Schema: 14
- Safety: output omitted host, password, server name, framebuffer dimensions,
  pixel payloads, byte counts, cursor pixels, and raw error descriptions.

| Profile | Status | Samples | Delivered FPS | Update avg/p50/p95 ms | Tail >=250ms / >=1000ms | Tail content/full-dirty/full-upload |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| local-low-latency | mixed-updates | 36 / 36 | 4.32 | 191 / 39 / 515 | 7 / 1 | 3 / 1 / 1 |

Additional aggregates:

- Empty/content/timeouts: 6 / 30 / 0
- Renderer partial/full uploads: 29 / 1
- Dirty-area max: 1000 permille
- ContinuousUpdates standalone probe: failed with
  `continuous-probe-receive-connection-failed`

Interpretation:

- The new tail buckets confirm one very-slow update at or above 1000 ms and one
  slow frame that also had full-dirty/full-upload classification.
- Slow frames were not exclusively full-dirty/full-upload: 7 updates crossed the
  250 ms threshold, while only 1 of them was full-dirty/full-upload. Next
  optimization should keep request/response pacing and server repaint cadence in
  scope, not only renderer upload strategy.
- ContinuousUpdates remains unsuitable as the default transport for this
  endpoint.
