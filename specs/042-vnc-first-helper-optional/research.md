# Research: VNC-First, Helper-Optional Presentation

**Feature**: `specs/042-vnc-first-helper-optional` · 2026-09-07

## Measured before the spec (founder's Mac, 2026-09-06/07)

- Helper video primary with the VNC session still attached: `nettop`
  showed the helper process sending 21–115 KB/s and `screensharingd`
  sending ~420 KB/s to the same phone at the same time. The VNC stream is
  not paused while video is primary — FR-008's premise.
- Helper capture geometry: `SCDisplay` reports 1512×982 points; readability
  bucket scales to 960×624 (even-rounded). VNC `ServerInit` on the same
  Mac: 3024×1964. Aspect 1.5385 vs 1.5397 — a 0.08% difference, not a
  visible offset. The "cursor offset" the founder saw is two cursors
  (Mac's baked pointer + Naru's trackpad glyph), not a mapping error.
- `SCStreamConfiguration.showsCursor = true` at both capture sites in
  `NaruHelperVideoScreenCaptureKitAccessUnitSource.swift` (display and
  window paths).
- The helper app never called a prompting permission request, so macOS
  did not list it under Screen Recording; fixed in spec 041's app
  (`HelperAppModel.openPermissionSettings`, commit 35af9da4). Recorded here
  because it produced the silent-fallback session that motivated P3.

## R1 — live `showsCursor` toggle

**Question**: does `SCStream.updateConfiguration(_:)` apply a changed
`showsCursor` without restarting the stream on macOS 14/15, and does the
encoder need a forced keyframe afterwards?
**Status**: open — Round C measures it on the founder's Mac with the
existing `BenchmarkHelperVideoProbe` path and records the answer here.
**Default if unmeasured**: restart the stream on mode change (the phone
already tolerates a restart through keyframe recovery, spec 019).

## R2 — pinch dead over the helper-video preview

**Question**: which branch of `SessionViewportView` renders on the
founder's iPhone in helper-video mode, and why does `onPinch` not reach
`applyZoomScale`?
**Status**: open — Round E-inv writes the failing test or proves the path.
**Candidates** (from reading, unverified): (a) `MetalFramebufferInputOverlayView`
pinch recogniser not installed when `framebuffer == nil`; (b) the
`.aspectRatio(…, contentMode: .fit)` container clips the overlay's hit area
in portrait fill-baseline; (c) a `usesHelperVideoPrimaryPreview` branch
that reaches `helperVideoLayerPreviewWithoutFramebuffer()` (no gestures)
even though VNC frames exist.

## R3 — Screen Sharing after a request pause

**Question**: after minutes without `FramebufferUpdateRequest`, does macOS
Screen Sharing answer a full (non-incremental) request with the whole
frame promptly, or does it need a client-side nudge (e.g. a fresh
`SetEncodings`)?
**Status**: open — Round D measures against the live Mac
(`NARU_LIVE_MAC_*`), unit gate on `FakeRFBServerKit` regardless.
