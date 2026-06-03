# Sustained Duration Candidate Comparison

Date: 2026-06-04 KST

Purpose: use the schema v17 duration-only stream-shape benchmark to compare
practical sustained-session tuning candidates before changing production VNC
defaults. This artifact stores only redacted aggregate benchmark output. It does
not include target identity, framebuffer dimensions, coordinates, pixels,
cursor pixels, byte counts, raw payloads, raw errors, or credentials.

## Research Notes

- RFC 6143 keeps framebuffer updates request-driven and explicitly allows fast
  clients to regulate incremental request rate to avoid excessive traffic.
- TigerVNC exposes automatic encoding selection plus preferred encoding,
  compression level, quality level, and a 17 ms pointer-event interval; this
  supports benchmark-backed tuning rather than one fixed global setting.
- IANA records ContinuousUpdates/Fence as RFB extensions, so Naru should keep
  request/response as the compatibility baseline unless a live server proves
  the extension path is safe.

References:

- https://www.rfc-editor.org/rfc/rfc6143
- https://tigervnc.org/doc/vncviewer.html
- https://www.iana.org/assignments/rfb/rfb.xhtml

## Command Shape

All runs used:

- `VNCLiveBenchmark`
- schema v17
- `--attempts 1`
- `--full-refresh-samples 0`
- `--stream-shape-samples 0`
- `--stream-shape-empty-backoff app`
- `--first-frame-profiles none`
- `--continuous-update-samples 1`

## Pacing / Power Candidates

All pacing candidates used `local-low-latency`, request/response transport, a
20 second duration cap, and `--stream-shape-idle-frame-interval 0.05`.

| Candidate | Power mode | Content interval | Elapsed ms | Received | Content | Empty | All-update FPS | Content-frame FPS | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| normal 60 Hz-class | normal | 0.0166667 s | 20005 | 135 | 107 | 28 | 6.75 | 5.35 | 119 | 26 | 484 | 16 | 1 | mixed-updates |
| normal 30 Hz-class | normal | 0.0333333 s | 20004 | 110 | 94 | 16 | 5.50 | 4.70 | 141 | 40 | 498 | 20 | 0 | mixed-updates |
| low-power 60 Hz config | low-power | 0.0166667 s | 20004 | 98 | 83 | 15 | 4.90 | 4.15 | 147 | 52 | 498 | 18 | 0 | mixed-updates |

## Transport Candidate

The transport comparison used `local-low-latency`, normal power, 60 Hz-class
content interval, request/response vs ContinuousUpdates, and a 15 second
duration cap.

| Transport | Elapsed ms | Received | Content | Empty | All-update FPS | Content-frame FPS | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| request-response | 15006 | 101 | 88 | 13 | 6.73 | 5.86 | 121 | 28 | 473 | 12 | 1 | mixed-updates |
| continuous-updates | 0 | 0 | 0 | 0 | n/a | n/a | n/a | n/a | n/a | 0 | 0 | failed |

## Encoding / Adaptive Profile Candidates

Profile candidates used request/response transport, normal power, 60 Hz-class
content interval, and a 10 second duration cap.

| Profile | Elapsed ms | Received | Content | Empty | All-update FPS | Content-frame FPS | Avg update ms | P50 update ms | P95 update ms | Slow >=250 ms | Very slow >=1000 ms | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| local-low-latency | 10005 | 57 | 49 | 8 | 5.70 | 4.90 | 144 | 29 | 483 | 8 | 1 | mixed-updates |
| tight-first | 10010 | 77 | 65 | 12 | 7.69 | 6.49 | 102 | 28 | 481 | 8 | 0 | mixed-updates |
| zrle-compression-0 | 10004 | 75 | 66 | 9 | 7.50 | 6.60 | 105 | 29 | 488 | 9 | 0 | mixed-updates |
| adaptive-good-full | 10005 | 79 | 69 | 10 | 7.90 | 6.90 | 98 | 21 | 482 | 9 | 0 | mixed-updates |
| adaptive-poor-full | 10013 | 73 | 64 | 9 | 7.29 | 6.39 | 105 | 27 | 480 | 9 | 0 | mixed-updates |

## Decision

Keep the production request/response compatibility path conservative:
ContinuousUpdates failed on this macOS Screen Sharing target and should remain
opportunistic rather than forced.

Keep 60 Hz-class normal-mode content pacing as the best current responsiveness
default. The 30 Hz and low-power candidates lower update pressure, but they also
lower delivered content FPS in these sustained runs. Low Power Mode remains the
right explicit heat/battery lever.

Treat adaptive-full encoding profiles as a next investigation target, not a
default change yet. The short profile sweep suggests the adaptive-good-full
encoding list can improve sustained content FPS on this target, but the sample
is too short and local-low-latency/tight-first variance needs a longer physical
iPhone pass before enabling automatic adaptive renegotiation by default.

Residual risk:

- These are localhost/macOS Screen Sharing runs, useful for relative direction
  but not final phone thermal comfort.
- The profile sweep is 10 seconds per candidate. Use a 1/5/30 minute physical
  iPhone run before claiming sustained UX or heat improvements.
