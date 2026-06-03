# Duration Stream-Shape Smoke

Date: 2026-06-04 KST

Purpose: verify `VNCLiveBenchmark` schema v17 can run a sustained
duration-only stream-shape probe against a live VNC server. This artifact stores
only redacted aggregate benchmark output. It does not include target identity,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
payloads, raw errors, or credentials.

## Research Notes

- RFC 6143 keeps normal framebuffer updates request-driven and notes that a
  fast client may regulate incremental `FramebufferUpdateRequest` rate to avoid
  excessive traffic.
- TigerVNC exposes automatic encoding selection plus preferred encoding,
  compression, quality, and 17 ms pointer-event interval controls, reinforcing
  that practical VNC performance depends on server, link, and device behavior.
- IANA records ContinuousUpdates/Fence as RFB extensions, so sustained runs
  should keep comparing request/response and extension transport modes before
  changing production gates.

References:

- https://www.rfc-editor.org/rfc/rfc6143
- https://tigervnc.org/doc/vncviewer.html
- https://www.iana.org/assignments/rfb/rfb.xhtml

## Command Shape

The run used:

- `VNCLiveBenchmark`
- schema v17
- `--attempts 1`
- `--full-refresh-samples 0`
- `--stream-shape-samples 0`
- `--stream-shape-duration-seconds 6`
- `--stream-shape-frame-interval 0.0166667`
- `--stream-shape-idle-frame-interval 0.05`
- `--stream-shape-empty-backoff app`
- `--stream-shape-power-mode normal`
- `--first-frame-profiles none`
- `--stream-shape-profiles local-low-latency`
- `--stream-shape-transport request-response`
- `--continuous-update-samples 1`

The duration cap also bounded each in-flight update wait and post-update pacing
delay to the remaining duration.

## Result

| Duration cap | Elapsed ms | Requested | Received | Status | All-update FPS | Content-frame FPS | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms |
| ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 6 s | 6005 | 29 | 29 | mixed-updates | 4.83 | 4.16 | 169 | 33 | 485 | 4 | 1 |

## Interpretation

The duration-only run proves `--stream-shape-samples 0` no longer disables the
probe when `--stream-shape-duration-seconds` is present. Schema v17 records the
duration cap and produces the same aggregate stream-shape summary as sample
runs. The elapsed duration stayed within about one frame-pacing interval of the
6 second cap, which is the baseline needed for longer 1/5/30 minute thermal and
FPS experiments.

Residual risk:

- This was a short localhost/macOS Screen Sharing smoke. It validates the
  benchmark path, not physical iPhone heat or battery behavior.
