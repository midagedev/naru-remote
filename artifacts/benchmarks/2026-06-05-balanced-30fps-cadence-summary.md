# 2026-06-05 Balanced 30fps Cadence Summary

## Trigger

The sustained iPhone usability goal now has a fresh localhost macOS Screen
Sharing signal after the balanced ZRLE default and gesture/Compose fixes. The
question was whether the production balanced request/response loop should keep
requesting content frames at 60fps-class cadence, or start at the same 30fps
floor used by adaptive pressure and power-saver pacing.

## Research Direction

- RFC 6143 says a fast client may regulate incremental
  `FramebufferUpdateRequest` rate to avoid excessive network traffic.
- TigerVNC documents automatic selection of encoding and pixel format based on
  connection speed, and exposes compression/quality controls. Naru does not yet
  expose manual performance controls, so the balanced default must be a safe
  sustained iPhone default.

## Live Localhost VNC Evidence

Safety boundary: these runs are redacted aggregate benchmark output only. They
omit host, password, server name, framebuffer dimensions, coordinates, pixels,
byte counts, cursor pixels, compressed payloads, raw error descriptions, and
raw per-frame timing samples.

Command shape:

```sh
NARU_LIVE_MAC_HOST=127.0.0.1 NARU_LIVE_MAC_PORT=5900 \
NARU_LIVE_MAC_PASSWORD='[redacted]' swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --continuous-update-samples 1 \
  --first-frame-profiles none \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 12 \
  --stream-shape-profiles local-low-latency \
  --stream-shape-transport request-response \
  --stream-shape-empty-backoff app \
  --stream-shape-client-pressure app \
  --timeout 8 \
  --idle-timeout 0.75
```

| Active request cadence | Actual encoding | Content FPS | Update avg/p95 ms | Client-processing p95/max ms | Adaptive pressure pacing | Renderer partial/full |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 60fps-class, 0.0167s | ZRLE only | 4.75 | 126 / 492 | 138 / 156 | 319 permille | 57 / 0 |
| 45fps-class, 0.0222s | ZRLE only | 5.08 | 152 / 495 | 13 / 2109 | not reported | 60 / 1 |
| 30fps-class, 0.0333s | ZRLE only | 4.33 | 153 / 506 | 8 / 11 | 0 permille | 52 / 0 |

## Decision

Switch the balanced production active request interval from 60fps-class to
30fps-class pacing, and make the live benchmark default match the app. Keep
explicit zero-delay fake/test paths and benchmark-provided intervals unchanged.

## Rationale

The 60fps-class run did not buy meaningful content FPS on the current macOS
Screen Sharing target, but it did create client-processing tail pressure that
activated adaptive pacing for nearly a third of samples. The 30fps-class run
kept the same actual ZRLE encoding and similar real content FPS while holding
client-processing p95 to a single-digit millisecond bucket with no adaptive
activation. The 45fps probe had one full-dirty/full-upload outlier and a very
large max client-processing sample, so it is not the balanced default.

This changes the starting point, not the ceiling of the architecture: future
adaptive link modes can still raise cadence for servers that actually deliver
higher content FPS without local pressure.

## Verification

- `swift run VNCLiveBenchmark` 60fps-class 12 second run above.
- `swift run VNCLiveBenchmark` 45fps-class 12 second run above.
- `swift run VNCLiveBenchmark` 30fps-class 12 second run above.

## Residual Risk

Physical iPhone heat/FPS still needs a sustained on-device pass. This evidence
is strongest for the current localhost macOS Screen Sharing target; other VNC
servers may behave differently.
