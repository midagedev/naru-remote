# Trackpad Hot Cursor Summary - 2026-06-07

## Goal

Close one concrete class of "half-beat late" zoomed trackpad navigation on
iPhone: when the visible cursor is near the viewport follow zone, a small
finger sample should still visibly move the cursor instead of being almost
entirely consumed by viewport auto-pan.

## Finding

The existing square-viewport resolver tests kept central movement finger-paced,
but they did not cover the phone portrait + wide desktop shape that dominates
real VNC usage. A new synthetic sequence for a 1920x1080 remote desktop inside a
390x520 phone viewport reproduced the lag class: after several small 6 pt
samples, edge-follow auto-pan consumed enough of each sample that the visible
cursor advanced only about 2.1 pt.

That is mathematically smooth, but it feels delayed: the viewport is moving, yet
the actual remote cursor appears to trail the finger.

## Change

- The Metal host now passes its current hot cursor into the app-model trackpad
  resolver path. The model's coalesced published cursor remains a SwiftUI mirror,
  not the source of truth for the next hot-path sample or click.
- Zoomed trackpad edge-follow auto-pan now caps reveal movement below half of the
  current touch delta, preserving visible cursor travel while the viewport still
  catches up.
- Added app-model tests proving drag and tap use the host-local hot cursor before
  the published cursor mirror flushes.
- Added a wide-desktop/phone-portrait resolver sequence that fails when visible
  cursor travel falls below half the touch sample.

## Evidence

- `swift test --filter PointerGestureResolverTests` passed after the cap change.
- `swift test --filter TrackpadModeModelTests` passed with the hot-cursor
  contract tests.

## Residual Risk

This is a deterministic geometry and ownership fix. It still needs physical
iPhone verification because UIKit recognizer cadence, ProMotion timing, and live
remote cursor rendering differ from SwiftPM geometry tests.
