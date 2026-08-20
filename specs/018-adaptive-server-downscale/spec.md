# Feature Specification: Adaptive Server-Side Downscale (Apple ScaleFactor)

**Feature Branch**: `018-adaptive-server-downscale`
**Created**: 2026-08-20
**Status**: Implemented 2026-08-20 (ladder + Apple gate + pointer mapping;
live gates green). Founder device pass residual (sharpness at fit + zoom
round-trip on a real phone).
**Product**: Naru Remote
**Input**: Founder direction 2026-08-20 "계속해서 개선해서 출시품질 가자" +
bandwidth question 2026-08-19. Research: NEXT_STEPS 1f lever ③,
`artifacts/research/2026-08-20-streaming-performance-levers.md` (addendum).

## Ground Truth (live-measured 2026-08-20, three consecutive runs)

- Apple Screen Sharing honors the proprietary `ScaleFactor` client message
  (type 0x08, `u8 reserved + f64 BE scale`) **on the standard VNC-password
  auth path**: scale 0.5 → full-update extent ratio exactly 0.50 × 0.50
  (4× fewer pixels per frame). This is what Screens 5 sells as
  "Compression".
- The resize arrives as a standard **DesktopSize (-223) pseudo-encoding**;
  `RFBFramebufferDecoder` already resizes the framebuffer and
  `RFBNetworkClient` already refreshes `clientServerInit`
  (`didResizeDesktop` path, spec 004 FR-008). No decoder work needed.
- Restore to 1.0 works in the same session but lazily (~1s, second full
  update) → the ladder needs hysteresis, never a reconnect.
- `RFBClientMessageEncoder.appleScaleFactor` + 
  `RFBNetworkClient.sendAppleScaleFactor` exist (probe-only, commit
  `e73a7d82`). No production caller yet.
- **Danger**: RFB has no client-message length negotiation — sending 0x08
  to a non-Apple server desyncs the session (the server cannot skip an
  unknown-length message). The Apple gate is a hard safety requirement,
  not an optimization.

## Why

A phone at fit-to-screen cannot display a 2.5K–6K Mac framebuffer's pixels
anyway — every un-zoomed frame carries 4× the pixels the screen can show.
Spec 017 covers the zoomed-in case (region-scoped requests, though Apple
under-clips when busy); this feature covers the zoomed-out case with a
lever Apple's server *does* honor. Together: zoomed-out = half-resolution
full frame, zoomed-in = full-resolution viewport region.

## Requirements

- **FR-001 (Apple gate — safety)**: The `ScaleFactor` message MUST only be
  sent on sessions whose RFB handshake advertised an Apple security type
  (30, 33, 35, or 36 in the server's security-type list). The client
  records the negotiated handshake's advertised types; any other server
  never receives the message. Sessions that never pass the gate behave
  byte-identically to today.
- **FR-002 (lossless-only ladder)**: v1 ladder is {1.0, 0.5}. Request 0.5
  only while BOTH hold: (a) the viewport is not zoomed in
  (`ViewportTransform.isZoomed == false`), and (b) the downscale is
  visually lossless for the current view, evaluated against the
  **unscaled** framebuffer:
  `transform.displayScale × currentAppliedRung × displayPixelsPerPoint ≤ 0.5`
  (one downscaled framebuffer pixel still maps to ≥ 1 device pixel). The
  `× currentAppliedRung` normalization is load-bearing (amended 2026-08-20,
  found in lead review of the first implementation, FAIL-first in
  `testStaysDownscaledAfterServerResizeAppliesTheHalfFramebuffer`): once
  0.5 applies, DesktopSize halves the framebuffer and `displayScale`
  doubles — the raw condition re-read against the scaled transform flaps
  the ladder 0.5↔1.0 every hysteresis window. The view layer supplies
  `displayPixelsPerPoint` from the SwiftUI `displayScale` environment;
  when unknown the policy assumes 3 (iPhone worst case — errs toward NOT
  downscaling).
- **FR-003 (instant upscale, lazy downscale)**: Zooming in past fit MUST
  request 1.0 on the next update-request tick (sharpness is the user's
  explicit intent). Downscale requires the eligible state to hold for 10
  consecutive update-request ticks (hysteresis against pinch flapping —
  same constant family as the spec 017 heartbeat).
- **FR-004 (resize ride-through)**: Framebuffer resizes ride the existing
  DesktopSize path. While the published `ViewportTransform.framebufferSize`
  disagrees with the live `serverInit` (mid-transition), the policy holds
  its last decision (no message).
- **FR-005 (scope)**: The ladder applies to every stream profile including
  power saver (server downscale saves power). PiP/watch preview and the
  helper-video lane are untouched (helper has its own future ladder).
- **FR-006 (privacy)**: No framebuffer dimensions, coordinates, or scales
  tied to dimensions in logs or exports. The applied rung (1.0/0.5) MAY
  appear in `SessionStreamStats`-class internal state.
- **FR-007 (boundary)**: The app model reaches the message through a new
  capability protocol on `RFBClientBoundary` (`RFBServerScalingClient`),
  never `RFBNetworkClient` concretely; tests drive it with a fake
  conforming connector.
- **FR-008 (pointer input space — live-measured 2026-08-20)**:
  screensharingd's pointer input space stays the **unscaled** framebuffer
  while ScaleFactor is applied: a scaled-coordinate PointerEvent landed at
  exactly half the physical center, and full-framebuffer coordinates
  landed with 0.0pt error
  (`LiveMacPointerHoverTests/testScaledSessionPointerInputSpaceStaysUnscaled`
  gates both halves). The model therefore multiplies outbound pointer
  coordinates back into unscaled space at its single pointer choke point
  (`enqueuePointerCommands` →
  `AppleServerDownscalePolicy.pointerCoordinateMapping`, half-shape
  detection ±2px). The unscaled baseline is captured at the moment the
  0.5 request is sent (the framebuffer is still unscaled then) — pointer
  traffic alone MUST NOT establish it (a first tap after the resize would
  adopt the scaled width and land at half position; FAIL-first in
  `testPointerCoordinatesMapToUnscaledSpaceWhileDownscaled`).

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — new `AppleServerDownscalePolicyTests` (Core) | ladder truth table: gate off → never; zoomed → 1.0 immediately; eligible → 0.5 only after 10 ticks; lossless condition boundaries; mid-resize hold |
| `swift test` — `NaruRemoteAppModelTests` (FAIL-first) | model sends 0.5 exactly once when eligible-for-10-ticks on an Apple-gated fake connector; sends 1.0 on zoom-in; never sends on a non-Apple fake connector |
| `swift test` — existing `LiveMacRFBSmokeTests` probe | wire behavior vs the real server (already green) |
| `swift test` — `LiveMacPointerHoverTests/testScaledSessionPointerInputSpaceStaysUnscaled` (env-gated) | the FR-008 ground truth: scaled coords do NOT inverse-map, full-framebuffer coords land exactly — the contract the client-side multiplier stands on |
| `swift test` — `testPointerCoordinatesMapToUnscaledSpaceWhileDownscaled` (FAIL-first) | the model doubles outbound pointer coordinates once the resize lands |
| iPhone simulator UI suites | session identifiers/behavior unchanged |
| Founder device pass (residual) | felt sharpness at fit + zoom round-trip |

## Residual Risk

- ~~Pointer mapping while scaled is inferred from Screens' behavior~~ —
  measured 2026-08-20 and closed by FR-008 (the inference was wrong: the
  server does NOT inverse-map; the client now maps).
- A Mac resolution change that happens *while scaled* momentarily
  mis-adopts the new scaled size as the unscaled truth; it self-corrects
  on the next restore round-trip. Rare, bounded, documented in
  `pointerCoordinateMapping`'s doc comment.
- Third-party servers are protected by FR-001's hard gate; the residual is
  a server that advertises Apple types but is not screensharingd (no such
  server known).
- Sharpness at 0.5 during brief zoom transitions is bounded by FR-003's
  instant-upscale rule; the founder's device pass judges the feel.
