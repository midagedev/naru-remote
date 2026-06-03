# Fast Content Request Pacing Comparison

Date: 2026-06-04 KST

Purpose: compare request/response content-frame pacing candidates after the
Tight-first default encoding change, using only redacted aggregate stream-shape
metrics. No target identity, framebuffer dimensions, coordinates, pixels, cursor
pixels, byte counts, raw payloads, or raw errors are stored here.

## Research Notes

- RFC 6143 keeps RFB framebuffer updates demand-driven: a client sends
  `FramebufferUpdateRequest`, and a fast client may regulate incremental request
  rate to avoid excessive traffic.
- TigerVNC's viewer auto-selects encoding and pixel format by link speed, and
  exposes manual preferred encoding, compression level, and JPEG quality knobs.
  That matches Naru's current benchmark-first tuning approach.
- TightVNC notes describe Tight compression levels as a CPU/performance tradeoff
  and cursor-shape updates as a way to avoid framebuffer updates for mouse
  movement.

References:

- https://www.rfc-editor.org/rfc/rfc6143
- https://tigervnc.org/doc/vncviewer.html
- https://www.tightvnc.com/whatsnew.php

## Command Shape

All runs used:

- `VNCLiveBenchmark`
- schema v15
- `--first-frame-profiles none`
- `--stream-shape-profiles local-low-latency`
- `--stream-shape-transport request-response`
- `--stream-shape-idle-frame-interval 0.05`
- `--stream-shape-empty-backoff app`
- `--continuous-update-samples 1`

Only `--stream-shape-frame-interval` and sample count varied.

## Initial 36-Sample Sweep

| Content request interval | All-update FPS | Content-frame FPS | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms | Slow content | Full uploads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0.0333333 s | 4.20 | 3.39 | 197 | 41 | 498 | 7 | 1 | 4 | 1 |
| 0.0166667 s | 7.85 | 6.54 | 100 | 26 | 478 | 4 | 0 | 0 | 0 |
| 0 s | 8.34 | 7.19 | 112 | 37 | 498 | 7 | 0 | 3 | 0 |

## 60-Sample Confirmation

| Content request interval | All-update FPS | Content-frame FPS | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms | Slow content | Full uploads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0.0166667 s | 5.77 | 4.71 | 146 | 31 | 489 | 10 | 1 | 2 | 1 |
| 0 s | 7.57 | 6.44 | 123 | 39 | 499 | 10 | 0 | 2 | 0 |

## Decision

Move the app default active content-frame interval from about 33 ms
(`1/30`) to display-rate-class 16.7 ms (`1/60`).

Rationale:

- The 36-sample sweep showed the 33 ms cap was leaving visible throughput on the
  table after the Tight-first default encoding change.
- `0 s` was fastest, but it is an unbounded active-content request loop when the
  server has real updates. For sustained iPhone use, `1/60` is a better default:
  it removes most avoidable client-side sleep while preserving a display-rate
  cap and leaving thermal floors meaningful.
- Empty/static-screen pacing is unchanged: idle updates still use the separate
  `0.05 s` idle interval plus app-mode sustained empty-update backoff.

Residual risk:

- These are localhost/macOS Screen Sharing runs. They are good for relative
  regression direction, not for final phone heat or battery claims. A physical
  iPhone sustained-session pass remains required before claiming thermal comfort.
