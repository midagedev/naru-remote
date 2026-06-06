# Trackpad Live Viewport Publish Summary - 2026-06-07

## Goal

Reduce the half-step feel during zoomed trackpad sessions without reopening
the heavier direct-touch pinch/pan path. Trackpad mode needs the server cursor
and nearby text echo to stay synchronized while the viewport follows the
cursor, especially after the `tight-first-cursor` app opt-in.

## Change

When a zoomed trackpad drag owns viewport interaction, the active frame
strategy is `liveRemoteFrames`. That strategy now also opts into bounded live
viewport-state publication:

- direct pinch/pan/deceleration: still publish SwiftUI/AppModel viewport state
  at gesture end
- zoomed trackpad cursor-follow: publish pending viewport state on a display
  link while the gesture is active
- `SessionViewportView` owns the policy branch; the Metal host only maps it to
  the private display-link cadence
- viewport-state display-link target: 60 Hz
- streamed framebuffer uploads during the gesture remain separately bounded by
  the existing live-frame throttle

## Expected Effect

The Metal layer still applies the visible transform immediately on the touch
hot path. The difference is that trackpad cursor-follow no longer waits until
gesture end before the model/PiP/request-region state sees the updated
viewport. That should make zoomed trackpad movement feel less split between
local panning and remote cursor/text echo.

## Verification

```bash
swift test --filter ViewportGestureRedrawThrottleTests
swift test --filter PointerGestureResolverTests
swift test --filter SessionViewportViewGeometryTests
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build
```

## Interpretation

This is a hand-feel improvement, not a traffic profile promotion. It keeps the
direct photo-like pinch/pan policy conservative while making the trackpad path
more live because that path is explicitly cursor-follow oriented.

## Privacy

This change adds no new diagnostics fields and emits no cursor positions,
request coordinates, dimensions, pixels, byte counts, host identity,
credentials, command text, draft text, marked text, or IME state.
