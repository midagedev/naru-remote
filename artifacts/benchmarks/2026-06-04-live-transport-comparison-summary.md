# Live Transport Comparison Summary

Date: 2026-06-04 KST

Target: local private VNC endpoint, redacted by `VNCLiveBenchmark`

Configuration:

- Tool: `swift run VNCLiveBenchmark --ask-password`
- Stream-shape transport: `both`
- Stream-shape empty backoff: `app`
- Frame interval: 0.033 seconds
- Idle frame interval: 0.05 seconds
- Idle timeout: 0.75 seconds
- Safety: output omitted host, password, server name, framebuffer dimensions,
  pixel payloads, byte counts, cursor pixels, and raw error descriptions.

Short local-low-latency run:

| Transport | Status | Samples | Delivered FPS | Update avg/p50/p95 ms | Empty/content/timeouts | Renderer partial/full |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| request-response | mixed-updates | 8 / 8 | 1.98 | 463 / 170 / 2115 | 2 / 6 / 0 | 5 / 1 |
| continuous-updates | failed | 0 / 8 | n/a | n/a | 0 / 0 / 0 | 0 / 0 |

All-profile request/response snapshot:

| Profile | Status | Samples | Delivered FPS | Update avg/p50/p95 ms | Empty/content/timeouts |
| --- | --- | ---: | ---: | ---: | ---: |
| local-low-latency | mixed-updates | 4 / 4 | 5.38 | 144 / 16 / 513 | 1 / 3 / 0 |
| tight-first | mixed-updates | 4 / 4 | 8.83 | 73 / 28 / 214 | 1 / 3 / 0 |
| zrle-first | mixed-updates | 4 / 4 | 9.55 | 63 / 15 / 190 | 1 / 3 / 0 |
| zrle-compression-0 | mixed-updates | 4 / 4 | 4.41 | 184 / 15 / 455 | 1 / 3 / 0 |
| adaptive-good-zrle | mixed-updates | 4 / 4 | 8.53 | 73 / 33 / 208 | 1 / 3 / 0 |
| adaptive-poor-zrle | mixed-updates | 4 / 4 | 8.91 | 69 / 16 / 214 | 1 / 3 / 0 |
| adaptive-good-full | mixed-updates | 4 / 4 | 9.85 | 59 / 9 / 201 | 1 / 3 / 0 |
| adaptive-poor-full | mixed-updates | 4 / 4 | 7.02 | 97 / 21 / 248 | 2 / 2 / 0 |

ContinuousUpdates overlay result:

- Every profile failed in continuous transport mode with a catalog-only
  `connection-failed` label.
- After phase-aware labels were added, the short verification run reported:
  - stream-shape matrix: `stream-continuous-updates-connection-failed`
  - standalone continuous probe: `continuous-probe-receive-connection-failed`

Interpretation:

- Do not enable ContinuousUpdates by default for this endpoint; request/response
  remains the only practical transport mode observed here.
- The all-profile snapshot suggests `adaptive-good-full`, `zrle-first`, and
  `tight-first` deserve longer runs before changing the app's initial encoding
  profile.
- The short sample size means these are direction-finding numbers only. Next
  validation should run longer physical iPhone sessions and compare heat/FPS
  with the same redaction rules.
