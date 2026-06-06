# Helper Video Probe-Only Summary

Date: 2026-06-07

## Scope

This run verifies that `VNCLiveBenchmark --helper-video-probe-only` can exercise
helper-video probes without requiring live VNC target credentials. The mode is
intended as a fast setup gate after installing the helper or changing macOS
Screen Recording permission.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, helper stderr, stimulus command text, or
stimulus output are recorded here.

## Command Shapes

```bash
NARU_HELPER_EXECUTABLE="$(launchctl getenv NARU_HELPER_EXECUTABLE)" \
swift run VNCLiveBenchmark \
  --helper-video-probe-only \
  --visual-transport helper-video \
  --helper-video-probe external-helper-synthetic-encoded-tcp \
  --json
```

```bash
NARU_HELPER_EXECUTABLE="$(launchctl getenv NARU_HELPER_EXECUTABLE)" \
swift run VNCLiveBenchmark \
  --helper-video-probe-only \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

## Synthetic External Helper Result

- Probe-only schema: `1`.
- Helper-video probe mode: `external-helper-synthetic-encoded-tcp`.
- Helper stream state: `healthy`.
- Startup band: `fast`.
- Sustained update band: `smooth`.
- Decode pressure: `low`.
- Fallback count bucket: `none`.
- Verdict: `pass`.
- Issue codes: none.

## ScreenCaptureKit External Helper Result

- Probe-only schema: `1`.
- Helper-video probe mode: `external-helper-screen-capturekit-tcp`.
- Helper stream state: `failed`.
- Startup band: `failed`.
- Sustained update band: `stalled`.
- Decode pressure: `notMeasured`.
- Fallback count bucket: `one`.
- Verdict: `fail`.
- Issue codes:
  `helper-video-permission-missing`,
  `helper-video-stream-unhealthy`,
  `helper-video-startup-failed`,
  `helper-video-sustained-stalled`,
  `helper-video-fallback-observed`.

## Interpretation

The external helper-video network and H.264 synthetic path can be checked
without live VNC target credentials and currently passes. The real
ScreenCaptureKit helper-video path is still blocked by missing Screen Recording
permission on the helper app bundle, but that failure is now visible through the
same short probe-only command that should pass after permission is granted.
