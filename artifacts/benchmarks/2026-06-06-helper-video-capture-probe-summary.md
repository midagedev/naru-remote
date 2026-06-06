# Helper Video Capture Probe Summary

Date: 2026-06-06

## Scope

This PR implements the first macOS helper-video prototype slice:
ScreenCaptureKit capture capability probing. It does not encode video, send
frames, start a helper-video stream, or change app defaults.

## Evidence

```bash
swift test --filter NaruHelperVideo
```

Result: 5 selected tests passed.

```bash
swift build --product NaruHelper
.build/debug/NaruHelper --video-capability
```

Result: build passed. The CLI smoke emitted fixed helper-video capability
labels only. On this machine, the safe state was Screen Recording permission
missing and capture source not checked.

## Safety Boundary

- The probe reports only fixed catalog labels for permission, capture-source
  state, capture API, availability, and safe failure code.
- The probe does not emit display identifiers, display names, window names,
  dimensions, frame content, endpoints, host names, byte counts, exact timings,
  OS error text, Compose text, clipboard contents, or credentials.
- Missing Screen Recording permission short-circuits before querying
  ScreenCaptureKit shareable content.

## Next Work

- Add VideoToolbox H.264 encoder prototype behind a helper feature flag.
- Add authenticated helper-video transport messages for capability and stream
  start.
- Add iOS decode/display prototype and constrained-cellular comparison once
  fake and live transport pieces exist.
