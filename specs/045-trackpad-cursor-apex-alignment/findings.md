# Spec 045 findings — root cause and fix (2026-09-19)

## Root cause

`TrackpadCursorGlyph.measureTipOffsetFromCenter`
(`NaruRemote/App/Features/SessionViewer/TrackpadCursorGlyph.swift`) scanned
its alpha buffer bottom-first (`row = height - 1 - y`) under the belief that
`CGContext` origin bottom-left flips the rows. In this pipeline — the glyph
drawn into a same-size alpha context — buffer row 0 IS the displayed top
row (verified with an ASCII dump of the buffer during the round: the
arrowhead sits at buffer rows 2+, the tail runs to the bottom rows).

The scan therefore returned the tail's bottom pixel (buffer x≈11.5, bottom
row) instead of the tip (buffer x≈3.5, row 2), producing
`tipOffsetFromCenter = (+2.67, -11.33)` instead of `(-5.33, -10.33)`.
Both render branches that use the fallback glyph (`MetalFramebufferView`
hot overlay and the `SessionViewportView` SwiftUI twin) parked the glyph
box ~8.3 pt too far left, so the drawn tip landed ~8.3 pt left of the
anchor at every zoom — constant in view points, exactly the reported
+8.7 pt (fit) / +8.0 pt (max). The server-cursor branch was measured as a
control and is exact (Δ +0.17 pt, scan granularity).

The founder's "solid near-white silhouette with no black outline, 11.7 ×
21 pt" is the thresholded fallback glyph body (box 17.67 × 25.67 pt, body
≈ 12/18 of the width, ≈ 22/26 of the height), confirming the founder's
session drew the fallback branch.

## Fix

Removed the row flip (two lines + comment). No change to `visualScale`
(FR-004), no artwork change, no twin-side change needed: both twins
consume the corrected static.

## Gate

`NaruRemote/Tests/NaruRemoteBenchmarkTests/TrackpadCursorApexAlignmentTests.swift`
renders the real host view to a bitmap and locates the tip with an
independent scan (never calls `tipPoint` / `measureTipOffsetFromCenter` /
`tipOffsetFromCenter`). FAIL-first on unmodified source: fallback Δx
−8.17/−8.50 at zoom 1, −8.17/−7.92 at zoom 4 (Δy < 1 everywhere); server
branch green. Post-fix: 5 tests, 0 failures.
`testCursorApexCharacterisation` prints the `[cursor-apex]` standing
numbers and stays assertion-free.
