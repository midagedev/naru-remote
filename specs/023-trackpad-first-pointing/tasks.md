# Tasks: Trackpad-First Pointing

**Feature**: `specs/023-trackpad-first-pointing/spec.md`
**Created**: 2026-08-21

## T001 — Trackpad becomes the product default ✅ 2026-08-21

`NaruRemote/Sources/NaruRemoteCore/SessionViewer/PointerControl.swift` —
`productDefault` is `.trackpad`, with the attribution comment.
`PointerControlTests.testProductDefaultIsTrackpad` replaces the assertion that
pinned `.directTouch` (deliberate product change, not a relaxed gate).

## T002 — Centre the cursor when the remote coordinate space arrives ✅ 2026-08-21

`NaruRemote/App/AppShell/NaruRemoteAppModel.swift` —
`centerTrackpadCursorIfUnplaced()` called from the single
`setInputCoordinateSpace(width:height:)` choke point. Only an *unplaced*
cursor moves, so a DesktopSize resize cannot teleport a positioned cursor.
Covered by `TrackpadModeModelTests.testConnectCentersAndShowsCursorWithoutAToggle`.

## T003 — Vertical breathing band in the pan clamp ✅ 2026-08-21

`NaruRemote/Sources/NaruRemoteCore/SessionViewer/ViewportTransform.swift` —
`verticalPanBand(viewSize:)` = `min(96, height * 0.16)`, applied inside
`clampPan` only when the vertical axis actually overflows. Single owner: the
auto-pan path in `PointerGestureResolver` already routes through `clampPan`, so
trackpad edge-follow reaches into the band with no extra wiring.

Gates (`ViewportTransformTests`, 6 new cases): band value and reach past flush,
symmetry, horizontal stays flush, no band while the content fits, the 96pt cap,
and `panToReveal` reaching into the band.

**FAIL-first measured**: with `verticalPanBand` forced to `0`, 4 of the 6 fail
(`testZoomedVerticalPanReachesPastFlushByTheBreathingBand`,
`testHorizontalPanStaysFlushWhileTheVerticalBandApplies`,
`testVerticalBandIsCappedForTallViewports`,
`testAutoPanRevealReachesIntoTheVerticalBand`); the two guard cases pass either
way by design.

## T004 — Cursor glyph hotspot ✅ 2026-08-21

`NaruRemote/App/Features/SessionViewer/TrackpadCursorGlyph.swift` (new) owns the
symbol, its point size, the rendered image, its natural box, and the measured
tip offset. `MetalFramebufferView` and `SessionViewportView` both place the
glyph through it; the Metal path also stopped forcing a 22×22 `scaleToFill` box.

Glyph geometry measured against the shipping artwork at 22pt: box 19×26pt, tip
pixel (3, 3) — i.e. the old centre-on-anchor placement drew the tip 6.5pt left
and 10pt above the clicked pixel.

Gates (`TrackpadCursorGlyphTests`, 7 cases): the raster tip scan against a
synthetic arrow, the offset math, the centre-placement round-trip, a regression
case that fails if the measured offset collapses to zero, and the non-square box.

**FAIL-first measured**: with the resolved tip offset forced to `.zero`,
`testCentrePlacementIsNotTheAnchorForTheShippingGlyph` fails with
`("0.0") is not greater than ("4.0")`.

## T005 — Live simulator gate ✅ 2026-08-21

`NaruRemote/UITests/TrackpadFirstPointingUITests.swift` (new), iPhone 17 Pro
simulator against this Mac's Screen Sharing:

- `testTrackpadIsLiveOnArrivalAndTheBottomRowCanBeParkedAboveTheDock` — asserts
  the pointer-mode control reports **Trackpad mode** on a fresh connect with no
  toggle tapped (`mode=trackpad`, passed), then zooms and drives the cursor to
  the bottom and captures the result.
- `testDrawnCursorTipProbe` — one deterministic drag, then a capture, for glyph
  inspection.

Captures land under the gitignored `artifacts/screenshots/local-mac-e2e/`
tree: they show the developer's live desktop and must not become repo content.

**Band verified visually, FAIL-first**: with `verticalPanBand` forced to `0`,
the remote screen's Dock row sits behind the floating Type/Compose pill (only
icon slivers visible either side of it). With the band, the same Dock row parks
fully visible above the pill with breathing space beneath it.

## T006 — Founder device pass ⏳ open

The felt gap on a real iPhone: trackpad on arrival, reaching the remote Dock
while zoomed, and whether the cursor tip now lands where the tap lands.

Note on the boundary of what the lead verified: the tip's placement is pinned
by arithmetic (measured glyph geometry + the single placement call) and by unit
tests. An absolute live "drawn tip vs host pointer" comparison was attempted and
dropped — reporting it would require printing framebuffer coordinates
(constitution §IV), and a cross-run differential is unreliable because zoom/pan
state differs between runs.
