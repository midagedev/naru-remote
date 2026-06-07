# Helper-Primary VNC Control Plane Summary - 2026-06-08

## Reproduction

- `helper-video-live-gate`: blocked before true capture by helper app Screen
  Recording permission. The runner reported the fixed
  `blockedByScreenRecordingPermission` gate and skipped impossible capture work.
- `remote-desktop-10fps-readiness`: physical iPhone gate remained blocked by
  local Xcode account/provisioning setup; helper synthetic and sustained
  synthetic H.264 paths passed; true ScreenCaptureKit helper-video remained
  permission-blocked.
- VNC product cadence still failed the 10fps target. The latest readiness run
  measured about 1.7 content fps with average update time around 514 ms and a
  first-byte-wait dominated receive path. No-network cadence drilldown improved
  only to about 5.5 content fps, still below the product floor.
- Encoding/profile sweeps did not rescue VNC cadence. Tight-first and
  cursor-first candidates fell back to raw rectangles and remained around
  1.1-2.0 content fps under constrained conditions.
- Local app-side renderer and helper synthetic paths were not the bottleneck:
  simulator framebuffer upload stayed in sub-millisecond to low-millisecond
  ranges, and synthetic H.264 access units through the app runner/sample-buffer
  path stayed around two milliseconds per measured batch.

## Decision

Helper-video is the primary smooth visual strategy. VNC remains the control,
input, diagnostic, reconnect, and fallback transport, but when helper-video is
the healthy foreground visual transport, VNC framebuffer requests are reduced to
the fixed helper-primary fallback sampling cadence instead of continuing the
ordinary visual request loop.

## Expected Product Effect

- Reduces VNC visual request pressure, receive-path work, and heat while the
  visible pixels come from helper-video.
- Preserves pointer, key, and composed text control over VNC.
- Keeps a recent VNC fallback framebuffer instead of fully parking visual reads.
- Wakes out of helper-primary sampling when helper-video stalls or falls back so
  ordinary VNC cadence resumes for recovery.

## Verification

- `swift test --filter 'NaruRemoteAppModelTests/testSessionStreamPacingPolicyUsesHelperVideoPrimaryVNCSamplingFloor|NaruRemoteAppModelTests/testHelperVideoPrimarySamplesVNCFallbackAndKeepsControlPathActive|NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport'`
- Result: passed.

## Privacy

This artifact uses fixed labels and coarse aggregate observations only. It does
not contain hostnames, endpoints, credentials, exact frame payloads, raw byte
counts, pixels, display identifiers, pointer coordinates, text payloads, or raw
OS error strings.
