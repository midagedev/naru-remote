# Helper Video iOS Decode Prototype Summary

Date: 2026-06-06

## Scope

This PR adds the first iOS-side helper-video decode/display prototype. It
parses helper-video Annex-B H.264 access-unit payloads, caches SPS/PPS
parameter sets through CoreMedia, converts displayable keyframe/delta units to
AVCC `CMSampleBuffer` values, and exposes an `AVSampleBufferDisplayLayer`
renderer.

It does not open a live helper-video listener, send captured screen frames,
change VNC visual defaults, run a constrained-cellular helper-video live
benchmark, or claim physical iPhone thermal/FPS behavior.

## Evidence

```bash
swift test --filter HelperVideoH264
```

Result: 9 selected tests passed.

The tests verify:

- Annex-B parser accepts three-byte and four-byte start codes.
- AVCC length-prefixed payloads are rejected before display.
- Parameter-set access units cache CoreMedia H.264 format state without
  emitting a display frame.
- Keyframe and delta units create ready compressed sample buffers with stable
  presentation cadence after parameter sets are available.
- End-of-stream resets cached format state.
- Missing binary payloads are rejected.
- The display renderer uses aspect-resize gravity and ignores parameter-set
  only access units.

## Safety Boundary

- Encoded H.264 payload bytes stay in memory only.
- The prototype does not write decoded frames, encoded payloads, dimensions,
  byte counts, host names, endpoints, pairing secrets, or exact per-frame
  timings to diagnostics or benchmark reports.
- Live helper transport and physical iPhone evidence remain required before
  promoting helper video beyond opt-in prototype status.
