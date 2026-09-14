# Feature Specification: Helper Video Cursor Alignment

**Feature Branch**: `044-helper-video-cursor-alignment`
**Created**: 2026-09-14
**Status**: Implemented 2026-09-14 — root-caused, fixed, gated. Gates: `swift test` 1959 tests / 0 failures (FAIL-first red captured before the fix: bounds 402×874 → 134×291.3, position (201, 437) → (189, 467)); iPhone 17 Pro simulator build green; `PiPFramingUITests` green; the live cursor-offset probe still puts the app's cursor on the Mac's real pointer exactly (app (567.2, 734.9) pt vs (567.0, 735.0) pt). **Open — founder device pass** (SC-1..SC-3), which needs a `Naru Helper.app` rebuilt from this tree.
**Product**: Naru Remote
**Input**: Founder, 2026-09-14, on a physical iPhone:

> "트랙패드 모드에서 앱에서 그려진 커서와 실제 녹호화면에 보이는 커서가
> 위치가 심하게 차이난다. 이거 맞춰줘"

and, after the first round of measurement:

> "vnc는 잘 동작해 헬퍼가 문제야"

## What was measured before anything was written

Three measurements narrowed this from "the cursor is wrong" to one line of
code. They are recorded here because each one closed a hypothesis that
reading the source had left open.

1. **The wire contract is exact.** `LiveMacPointerCoordinateSpaceTests`
   sends RFB `PointerEvent`s at known framebuffer pixels to this Mac's
   Screen Sharing server and reads back where the window server actually
   put the pointer. Served framebuffer 3024×1964 px against a 1512×982 pt
   display: every point landed with **0 pt of error** at exactly 0.5
   points per pixel. The Retina backing scale is the server's business and
   it does it correctly.
2. **The VNC client path is exact.** A DEBUG read-out on the drawn cursor
   (`naru.session.hotCursor.probe`) publishes the framebuffer pixel the app
   believes the pointer is at. Driving trackpad drags on the iPhone 17 Pro
   simulator against the live Mac and comparing with `CGEvent(source:
   nil)?.location` on the Mac: app `fb=1364.1,1496.0` → (682.05, 748.0) pt
   against a real pointer at **(682.0, 748.0) pt**. Zoomed (`zoom=1.052`,
   `pan=10.5`) it matched again: (570.95, 734.9) against **(571.0, 735.0)**.
3. **macOS never paints its pointer into the RFB framebuffer.** A vision
   pass over the simulator capture found exactly one cursor in frame — the
   app's own glyph. So *two* cursors can only be seen when the picture is
   helper video, which bakes the system pointer in through
   ScreenCaptureKit's `showsCursor`.

Those three together say the defect is not in the coordinates and not in
VNC. The founder confirmed the same from the device.

## Problem

**Root cause: the shared display layer is positioned with `frame` while a
viewport transform is live.**

`PiPSampleBufferDisplayLayerHostingView` hosts the
`AVSampleBufferDisplayLayer` that shows helper video, and it places that
layer with `layer.frame = bounds` — in `attach(layer:)`, which runs on
every SwiftUI `updateUIView`, and again in `layoutSubviews`. Separately it
applies the viewport as an affine transform on the same layer
(`translate(pan).scaledBy(zoom)`).

`CALayer.frame` is a derived property. Assigning it while `transform` is
not the identity is documented as undefined, and Core Animation resolves
it by inverting the live transform over the requested rect. Measured
directly (scale 3, translation (12, −30), container 402×874):

| | bounds | position |
| --- | --- | --- |
| after the transform is applied | 402 × 874 | (201, 437) |
| after `frame = bounds` | **134 × 291.3** | **(189, 467)** |

The layer shrinks by exactly the zoom factor and shifts by the pan, so the
transform that follows scales it straight back to the container: **the
video renders unzoomed and displaced**, while the cursor overlay — a
sibling view that maps framebuffer pixels through `ViewportTransform` —
keeps drawing at the real zoom and pan. The two disagree by a roughly
constant offset across the whole frame, which is exactly the shape the
founder reported ("어디서나 비슷한 방향·거리로 밀려 있다"). It does not
run away — a second assignment of the same rect is a fixed point, measured
(bounds stay 134×291.3 across three passes) — but the wrong geometry is
recomputed from scratch whenever the zoom changes, so it follows the user
around instead of settling.

The Metal VNC path is untouched by this because it never assigns a frame —
the `MTKView` is pinned with Auto Layout constraints and navigated with
`UIView.transform`. That is why VNC is fine and helper video is not.

Two structural facts made this possible and are part of the defect:

- **The placement of that layer has no owner.** Geometry (`frame`) is set
  in two methods and the transform in a third, on a layer that is *shared*
  with the PiP controller, so no single place can state what the layer's
  geometry is supposed to be.
- **There was nowhere to gate it.** The hosting view is iOS-only, and the
  repository's iOS unit-test target is the benchmark bundle; nothing that
  `swift test` runs could reach this code, so the class of defect had no
  test surface at all.

## Direction

**P1 — One owner for where the shared layer sits.** Bounds, position and
the viewport transform are decided in one place, expressed in properties
that are defined under a live transform, and the hosting view only calls
it.

**P2 — The owner is reachable by the fast gate.** It carries no UIKit, so
`swift test` can hold it to the invariant on every run rather than waiting
for a device pass.

**P3 — What the user sees decides.** The picture and the cursor overlay
are two renderings of one `ViewportTransform`; any code that can move one
without the other is the bug, whatever it looks like locally.

## Requirements

- **FR-001** The shared `AVSampleBufferDisplayLayer` is placed by setting
  `bounds` and `position`, never `frame`. Placing it twice in a row with a
  non-identity viewport transform live leaves its geometry unchanged.
- **FR-002** Placement and viewport transform have a single owner that
  compiles without UIKit, so `swift test` gates them.
- **FR-003** With the same container size, zoom and pan, the rect the
  video occupies on screen equals the content rect `ViewportTransform`
  reports for the same inputs, within a stated tolerance.
- **FR-004** The DEBUG cursor read-out
  (`naru.session.hotCursor.probe`) stays DEBUG-only so the Release
  submission contract's test-hook scan stays clean.
- **FR-005** No new user-content logging; cursor and layer geometry are
  not user-entered content and are neither logged nor persisted
  (constitution §IV).

## Success Criteria (device pass)

- **SC-1** In a helper-video session in trackpad mode, the drawn cursor
  sits on the system pointer baked into the video, anywhere on screen.
- **SC-2** Zooming and panning a helper-video session keeps them together.
- **SC-3** A helper-video session opens showing the picture at the same
  scale a VNC session does, and does not shrink over time.

## Verification matrix

| Layer | Command | Covers |
| --- | --- | --- |
| App unit | `swift test --filter NaruRemoteAppTests` | placement invariance under a live transform (FR-001/FR-002), content rect against `ViewportTransform` (FR-003) |
| iPhone simulator | `xcodebuild … 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'` | build + `TrackpadFirstPointingUITests` cursor-offset probe |
| Live Mac | `swift test --filter LiveMacPointerCoordinateSpaceTests` | the wire coordinate contract stays exact (the measurement that closed hypothesis 1) |
| Physical iPhone | founder | SC-1, SC-2, SC-3 |

## Out of scope

- Multi-display. The helper captures the main display only
  (`captureDisplay(from:)`) while the RFB framebuffer is the union of every
  attached display, so helper video cannot be geometrically right with more
  than one screen. The founder was on the built-in display alone for this
  report, so it is not this defect — recorded in `NEXT_STEPS.md`.
- The intermittent pointer-event drops measured on the server during this
  work (a move ignored for seconds while its neighbours land exactly).
  Characterised in `LiveMacPointerCoordinateSpaceTests`; not the reported
  symptom and not client-side.
