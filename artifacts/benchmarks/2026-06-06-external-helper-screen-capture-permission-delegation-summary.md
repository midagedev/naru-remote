# External Helper Screen Capture Permission Delegation Summary

Date: 2026-06-06

## Scope

This run verifies that `external-helper-screen-capturekit-tcp` is no longer
false-blocked by the benchmark process's Screen Recording permission state. The
benchmark setup preflight now delegates ScreenCaptureKit permission readiness to
the external helper process, and the helper-video report receives the helper's
own fixed permission failure label when permission is missing.

No host names, passwords, ports, helper executable paths, endpoints, frame
content, framebuffer dimensions, byte counts, raw OS errors, stimulus command
text, or stimulus output are recorded here.

## Commands

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --environment-preflight \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

```bash
swift build --product NaruHelper

NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 0 \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

## Result

- Environment preflight schema: `4`.
- Helper-video ScreenCaptureKit permission preflight status:
  `delegatedToHelper`.
- Preflight verdict: runnable with setup action `run-live-gate`.
- External helper ScreenCaptureKit probe: failed safely in the current helper
  process context with fixed issue code `helper-video-permission-missing`.
- The failure still includes fixed health/fallback labels only; no frame
  content, endpoints, helper executable paths, byte counts, display dimensions,
  raw errors, or exact helper timings are emitted.

## Interpretation

This removes the benchmark-process TCC false block from the external helper
path. A future stable helper process or bundle can now own Screen Recording
permission independently; once that helper context is granted permission, the
same benchmark mode can proceed to finite live ScreenCaptureKit capture instead
of being stopped by `VNCLiveBenchmark` itself.
