# App Stream Startup Preflight Gate Summary - 2026-06-05

## Baseline Target

The active practical target is `iphone-sustained-usability-v2`. This change
does not claim the target passes; it creates an app-side gate so one startup
variable can be tested safely on a physical iPhone before any production
default changes.

## Change Boundary

- Add `SessionStreamStartupPreflightPolicy` with production default disabled.
- Clamp hidden startup preflight to at most one incremental frame.
- Publish and record the first visible frame before attempting hidden preflight.
- Treat hidden preflight as best effort: timeout, cancellation, session change,
  or stream failure exits without surfacing hidden frame data.
- Cancel the hidden preflight task and frame pump when the parent stream task
  is cancelled during disconnect or profile change.
- Keep hidden frames out of framebuffer state, preview capture, and stream
  statistics.

## Verification

- `swift test --filter NaruRemoteAppModelTests/testStartupPreflight` passed.
- `swift test --filter
  NaruRemoteAppModelTests/testModelKeepsStreamingFramesAfterFirstFramebuffer`
  passed.

## Next Larger Unit

Use `iphone-sustained-usability-v2` as the gate for the next PR group:
sustained content FPS, direct zoom/pan smoothness, trackpad cursor behavior
while zoomed, and deterministic Compose routing on the physical iPhone path.
Before enabling this policy by default, mirror the final runtime boundary into
the active app-stream spec/plan as well as the benchmark feature notes.

## Privacy

This artifact intentionally records only policy labels, safe test scope, and
pass/fail verification status. It does not include host identity, credentials,
framebuffer dimensions, rectangle coordinates, pixels, cursor pixels, byte
counts, raw samples, raw payloads, hidden preflight frame contents, hidden
preflight timings, or raw error text.
