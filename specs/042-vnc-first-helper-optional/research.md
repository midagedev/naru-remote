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
**Status**: root-caused 2026-09-07 (Round E-inv, static trace + failing
test). Line numbers below are from the working tree during Round E-inv —
the file is under concurrent edit (Round B), so re-grep before citing.
Two defects; both are FR-009 violations.

**Cause 1 — primary, the founder's steady session (candidate b, refined).**
The live session viewport is always hero (`fillsAvailableHeight: true`,
`NaruRemoteAppShell.swift:544`). In that mode the VNC Metal path
deliberately skips the aspect fit — `if usesViewportFrame { preview }`
without `.aspectRatio` (`SessionViewportView.swift:2257–2266`) — so the
Metal view and its gesture recognizers cover the full viewport. The
helper-video path `sampleBufferLayerPreview` instead applies
`.aspectRatio(aspectRatio, contentMode: .fit)` **unconditionally**
(`SessionViewportView.swift:2009`), which shrinks the display layer AND
the hot input overlay (`MetalFramebufferInputOverlayView`, the view that
owns the shared `UIPinchGestureRecognizer` wiring) to the fit band. With
the founder's geometry (VNC `ServerInit` 3024×1964 in a ~430×812 hero
container) that band is 430×279 — one third of the screen height
(`HelperVideoPreviewGestureTests.testHeroContainerFitBandShrinksHelperPreviewGestureSurface`
computes it with the view's own `aspectFitSize`). A pinch with either
finger outside the band never reaches a recognizer, and the letterboxed
remainder has no gesture surface at all. The recognizer wiring itself is
intact and shared with the working VNC path
(`MetalFramebufferView.swift:978–1025` installs the pinch recognizer
unconditionally); nothing pointer-mode-specific gates it
(`usesMetalHotInputOverlay` has no pointer-mode input; re-pinned by
`testDeviceShapedHelperVideoSessionSelectsMetalHotInputOverlayInBothPointerModes`).

**Cause 2 — secondary, a fully gestureless window (candidates a+c,
unit-proven).** Helper video is selected *before* the RFB connect even
starts (`startHelperVideoStreamIfConfigured` runs at
`NaruRemoteAppModel.swift:3910`, ahead of `startFrameStream`). Between
helper acceptance and the RFB handshake the viewport renders
`helperVideoLayerPreviewWithoutFramebuffer()`
(`SessionViewportView.swift:2090`) whose input overlay is installed only
`if let inputCoordinateSpace` (line 2100) — and `inputCoordinateSpace`
is nil until `ServerInit` arrives. In that window a *playing* video has
zero gesture surfaces: pinch, pan, double-tap, and trackpad are all
dead. The same state persists for the whole session if the VNC connect
fails while the helper still streams.

**Failing test (Round D must turn green)**:
`NaruRemoteAppTests.HelperVideoPreviewGestureTests.testHelperVideoPrimaryKeepsGestureCapablePreviewStateWhileRFBHandshakeIsPending`
— drives the model through the real connect order (helper video accepted
and healthy while the RFB handshake is held pending) and asserts the
preview-deciding state is gesture-capable. Real failure message:
`XCTAssertTrue failed - FR-009 violated: helper video is the healthy
primary visual transport but the session viewport has no
gesture-capable preview state (latestFramebuffer == nil &&
inputCoordinateSpace == nil), so
helperVideoLayerPreviewWithoutFramebuffer renders without any input
overlay.` The file's other three tests pin currently-working behaviour
(device-shaped selector matrix, steady-state framebuffer + coordinate
space while helper-video primary, the fit-band geometry) and pass today.

**Recommended minimal fix (Round D implements)**: thread the hero/fill
flag into `sampleBufferLayerPreview` and skip the unconditional
`.aspectRatio` when filling (mirror `metalOrSampledPreview`'s
`usesViewportFrame` contract at `SessionViewportView.swift:2257`), so
the display layer and the hot gesture overlay cover the full hero
surface; and close the gestureless window by giving the no-framebuffer
helper branch a gesture surface when `inputCoordinateSpace` is nil (or
by deriving a coordinate space for helper-video-primary sessions, e.g.
from the stream descriptor geometry, before `ServerInit` lands). The
failing test covers the second half; the first half restores pinch over
the whole viewport and needs the founder device pass (SC-2).

**Why no simulator reproduction**: no launch-environment hook drives
`visualTransportMode == .helperVideo` with a live layer host in the app
process (`NARU_TEST_` grep: compose lifecycle, dock, pairing,
diagnostics, profile seeding, `UXAuditFixtures` tokens, and a
helper-video *health* storm that never selects the transport), and
building one is product code — out of Round E-inv's scope. The Metal
axis does not differ: `MetalFramebufferView.isSupported()` is true on
the iPhone 17 Pro simulator (iOS 26.2; probe: `MTLCreateSystemDefaultDevice()
!= nil = true, name=Apple iOS simulator GPU`). Founder device probe
(2 min): in a helper-video trackpad session, pinch starting over the
lower (letterboxed) half of the screen — pre-fix it does nothing; also
note the desktop letterboxes instead of filling. Post-fix, SC-2's pinch
pass covers both.

## R3 — Screen Sharing after a request pause

**Question**: after minutes without `FramebufferUpdateRequest`, does macOS
Screen Sharing answer a full (non-incremental) request with the whole
frame promptly, or does it need a client-side nudge (e.g. a fresh
`SetEncodings`)?
**Status**: measured 2026-09-07 (Round D, `LiveMacPostSilenceFullRequestTests`
against the live Mac, two runs). **Answered promptly, but with a
damage-only rectangle set** — the whole-frame assumption behind a
non-incremental request does not hold on Apple's server once the client
holds framebuffer state.

| run | baseline | post-120 s silence | follow-up request |
|-----|----------|--------------------|-------------------|
| 1 | 1488 rects, 3229 ms | 12 rects / 4634 px, 2301 ms | — |
| 2 | 1488 rects, 3199 ms | 14 rects / 5421 px, 2298 ms | healthy |

Findings:

- The connection survives the parked silence (120 s with no outstanding
  request) and answers the wake-path full request in ~2.3 s — well inside
  the FR-008 wake budget. No `SetEncodings`-style nudge is needed.
- But the answer is *sparse damage*, not the full framebuffer: 12–14
  rects (a few thousand changed pixels) where the fresh-connection
  baseline delivered the whole 1488-rect frame. Apple's server treats
  `incremental: false` as "resend everything" only when the client has no
  state; afterwards it sends current damage even for the non-incremental
  flag.
- Consequence for the FR-008 fallback wake path: the first post-fallback
  update cannot be assumed to be a complete repaint. That is fine in the
  app because the pump retains the pre-park framebuffer and composites
  damage onto it — the user sees the parked frame plus fresh damage, not
  a blank. It would matter only if the client ever *discarded* state
  across the park (it does not) or if the park coincided with a server-side
  framebuffer resize (`FramebufferSizeChange` forces the full-request
  reset path anyway).
- Gate treatment: the live test asserts the client invariants (answered
  within the 10 s budget, stream still in sync afterwards) and prints the
  rectangle-set verdict rather than asserting it — the extent is server
  behavior, not a client contract (same precedent as the region-scoped
  assertion in `LiveMacRFBSmokeTests`).
