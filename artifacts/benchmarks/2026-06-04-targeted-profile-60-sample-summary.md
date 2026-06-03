# Targeted Stream-Shape Profile 60-Sample Summary

Date: 2026-06-04 KST

Target: local private VNC endpoint, redacted by `VNCLiveBenchmark`

Configuration:

- Tool: `swift run VNCLiveBenchmark --ask-password`
- Full-refresh samples: 0
- Stream-shape samples: 60
- Stream-shape profiles:
  `local-low-latency,tight-first,zrle-compression-0,adaptive-good-full`
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
| local-low-latency | mixed-updates | 60 / 60 | 4.26 | 194 / 44 / 504 | 10 / 50 / 0 | 49 / 1 |
| tight-first | mixed-updates | 60 / 60 | 5.65 | 136 / 39 / 499 | 5 / 55 / 0 | 55 / 0 |
| zrle-compression-0 | mixed-updates | 60 / 60 | 5.44 | 143 / 42 / 507 | 7 / 53 / 0 | 53 / 0 |
| adaptive-good-full | mixed-updates | 60 / 60 | 5.43 | 142 / 39 / 501 | 12 / 48 / 0 | 48 / 0 |

ContinuousUpdates standalone probe:

- Status: failed
- Failure label: `continuous-probe-receive-connection-failed`

Interpretation:

- The comma-separated `--stream-shape-profiles` path works and preserved the
  selected profile order in schema-v13 output.
- `tight-first` led this targeted run by delivered FPS and average latency while
  avoiding full renderer uploads.
- `zrle-compression-0` and `adaptive-good-full` stayed close enough to keep as
  fallback/adaptive candidates.
- `local-low-latency` recovered from the earlier all-profile connect timeout,
  but it lagged the three candidates and included one full-upload-classified
  content frame in this run.
- A separate app-default PR should switch only after one more focused validation
  decides whether first-connect reliability or sustained stream latency matters
  more for the initial profile.
