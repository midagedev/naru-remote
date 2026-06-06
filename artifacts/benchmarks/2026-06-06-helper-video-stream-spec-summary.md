# Helper Video Stream Spec Summary

Date: 2026-06-06 KST

## Decision

Start `specs/007-host-helper-video-stream` as the next performance workstream.
The feature keeps VNC as the control, input, clipboard, reconnect, diagnostic,
and fallback transport while a paired Mac helper optionally provides a
low-latency compressed visual stream.

## Why This Is Next

The VNC-only path has already covered:

- Efficient RFB encodings and negotiation.
- RGB565 app candidates.
- Viewport-aware sustained request regions.
- Visible-glance first-frame startup regions.
- Renderer upload pressure checks.
- Request cadence, pacing, and outstanding-request depth experiments.

The latest request-pipeline live benchmark found that depth 2/3 did not reduce
the constrained-cellular sustained first-byte tail versus depth 1. The
remaining bottlenecks are now startup payload representation and server/update
source timing. Helper video changes that representation instead of asking the
same VNC server for more updates.

## Sources

- RFC 6143 RFB protocol: https://www.rfc-editor.org/rfc/rfc6143
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple VideoToolbox: https://developer.apple.com/documentation/videotoolbox
- Prior result: `artifacts/benchmarks/2026-06-06-request-pipeline-benchmark-summary.md`

## Safety Boundary

- Helper video is opt-in and private-network scoped.
- VNC remains the fallback and control path.
- First implementation milestones are benchmark-first; no product default
  promotion until benchmark-green and physical iPhone evidence exists.
- Diagnostics and benchmark artifacts may use only fixed labels and aggregate
  bands. They must not include frames, thumbnails, dimensions, coordinates,
  endpoints, host names, tokens, passwords, byte counts, exact per-frame
  timings, Compose text, or clipboard contents.

## Expected First Implementation Slices

1. Core helper-video state model and privacy-safe diagnostics.
2. Fake helper video stream and app visual transport selector while preserving
   VNC control.
3. Benchmark report shape for helper-video candidates.
4. macOS ScreenCaptureKit + VideoToolbox prototype behind an opt-in helper flag.
5. Live constrained-cellular comparison and physical iPhone gate.
