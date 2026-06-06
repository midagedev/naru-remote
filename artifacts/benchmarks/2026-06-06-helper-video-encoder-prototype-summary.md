# Helper Video Encoder Prototype Summary

Date: 2026-06-06

## Scope

This PR implements the first gated VideoToolbox H.264 encoder prototype. It
creates and prepares a synthetic compression session only when the helper flag
is explicitly enabled. It does not capture screen frames, encode captured
content, send helper-video access units, decode video on iOS, or change VNC
visual defaults.

## Evidence

```bash
swift test --filter NaruHelperVideoEncoder
```

Result: 6 selected tests passed.

```bash
swift build --product NaruHelper
.build/debug/NaruHelper --video-encoder-prototype
NARU_HELPER_VIDEO_ENCODER_PROTOTYPE=1 .build/debug/NaruHelper --video-encoder-prototype
```

Result: build passed. With the feature flag disabled, the helper reported a
disabled fixed-label state without preparing a session. With the feature flag
enabled on this Mac, the helper reported a prepared VideoToolbox H.264 session
using fixed catalog labels only.

## Safety Boundary

- The prototype is off by default.
- The disabled path does not create a VideoToolbox compression session.
- The enabled path prepares only a synthetic H.264 compression session.
- The probe does not emit display identifiers, display names, window names,
  dimensions, frame content, endpoints, host names, byte counts, exact timings,
  payloads, OS error text, Compose text, clipboard contents, or credentials.

## Next Work

- Add authenticated helper-video transport messages for capability and stream
  start.
- Add access-unit payload transport without logging or persisting encoded
  bytes.
- Add iOS decode/display prototype and constrained-cellular comparison once
  transport exists.
