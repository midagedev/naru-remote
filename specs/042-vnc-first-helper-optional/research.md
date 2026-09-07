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
**Status**: measured 2026-09-07 (Round C). The in-test live half is
**blocked on this Mac by macOS TCC content redaction** — not by a missing
permission in the ordinary sense — so the answer below separates what was
measured from what stays unverified, per the round's "record the exact API
result, don't guess" rule.

**In-test host (xctest runner) — redacted, exact API results.** The
SwiftPM test host cannot measure cursor compositing here:

- `CGPreflightScreenCaptureAccess()` returns **true** — misleading.
- `SCStream.startCapture` succeeds and delivers frames at exactly the
  requested rate (38 frames in 2.52 s at `minimumFrameInterval` 1/15),
  but **every frame is status idle (raw 0), zero `.complete`**, buffers
  carry static content: a CGWindowList-visible flipping probe window
  never appears, cursor warps never appear.
- `SCScreenshotManager.captureImage` returns a fixed 1920×1080 static
  placeholder while the display is 1512×982 points: parked-cursor
  shot pair is byte-identical, and the `showsCursor` true/false toggle
  has **zero** pixel effect (toggleDiff 0.0, re-measured in-test by
  `NaruHelperVideoPointerModeTests.skipIfScreenContentIsRedacted`, which
  now skips the live probes with this exact record on such hosts).
- This matches the repo's own `NaruHelperVideoPermissionIdentityContext`:
  SwiftPM build artifacts are unstable TCC targets, so the swift-test
  host's grant (even where preflight says true) does not deliver content.

**Granted process — measured working end-to-end.** The benchmark-granted
`.build/debug/NaruHelper` binary (stable path, real Screen Recording
grant) run with `--video-listen --video-source screen-capturekit
--video-frame-count 6` accepted a start request carrying
`pointerMode: trackpad` and streamed real frames:
`result=accepted`, units `parameterSet, keyframe, delta×5`, no stall
(`testExternalHelperProcessStreamsRealScreenFramesForBothPointerModes`,
gated `NARU_RUN_EXTERNAL_HELPER_PROCESS_TESTS=1`; the legacy nil-mode
request streams identically).

**Encoder keyframe half — no forced keyframe needed.** Five distinct
solid-color frames spanning a toggle window, encoded with
`keyFrameInterval` 10 000: kinds are exactly
`parameterSet, keyframe, delta, delta, delta, delta` — the encoder does
not inject a mid-sequence keyframe at the content change, so a cursor
compositing change travels as deltas and the existing wire
`requestKeyframe` covers the case where a decoder does want one
(`testEncoderEmitsNoMidSequenceKeyframeAcrossToggleWindow`).

**Decided mechanism.** The reliable mode switch is **the next start
request carrying the mode** — that path is measured end-to-end above and
the phone already tolerates a restart through keyframe recovery (spec
019). `NaruHelperVideoScreenCaptureKitRunningStream.updatePointerMode`
keeps `SCStream.updateConfiguration(_:)` as the cheap in-place attempt,
documented in-code as **unverified live** (blocked by the redaction
above): if the OS ignores a mid-stream `showsCursor` change the stream
keeps its prior cursor state, and the switch lands on the next start
request. Surfacing a live mid-session switch to the phone is Round D's
wire work (T-D4).

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
