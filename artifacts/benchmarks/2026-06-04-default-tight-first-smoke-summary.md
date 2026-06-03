# Default Tight-First Stream-Shape Smoke Summary

Date: 2026-06-04 KST

Target: local private VNC endpoint, redacted by `VNCLiveBenchmark`

Configuration:

- Tool: `swift run VNCLiveBenchmark --ask-password`
- Code under test: `RFBEncodingPreference.localLowLatency` switched to
  Tight-first with Hextile/Raw fallback
- Full-refresh samples: 0
- Stream-shape samples: 24
- Stream-shape profiles: `local-low-latency`
- Stream-shape transport: `request-response`
- Stream-shape empty backoff: `app`
- First-frame profiles: `none`
- Frame interval: 0.033 seconds
- Idle frame interval: 0.05 seconds
- Idle timeout: 0.75 seconds
- Schema: 13
- Safety: output omitted host, password, server name, framebuffer dimensions,
  pixel payloads, byte counts, cursor pixels, and raw error descriptions.

| Profile | Status | Samples | Delivered FPS | Update avg/p50/p95 ms | Empty/content/timeouts | Renderer partial/full |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| local-low-latency | mixed-updates | 24 / 24 | 4.34 | 191 / 29 / 485 | 3 / 21 / 0 | 20 / 1 |

ContinuousUpdates standalone probe:

- Status: failed
- Failure label: `continuous-probe-receive-connection-failed`

Interpretation:

- The benchmark-backed Tight-first default connected and sustained the
  request/response stream without sample loss in this smoke run.
- One tail-latency spike and one full-upload-classified frame kept the average
  lower than the earlier targeted 60-sample `tight-first` run; treat this as a
  post-change smoke, not a replacement for the longer comparison artifact.
- ContinuousUpdates remains unsuitable as a default for this endpoint.
