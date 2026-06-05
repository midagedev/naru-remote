# 2026-06-05 Trackpad Stream Continuity Summary

## Trigger

Physical-device feedback still reported unnatural zoom/pan and low perceived
frame rate. Code review found a regression against the earlier T015q intent:
every Metal-hosted trackpad drag claimed viewport interaction, even at fit scale
where cursor movement does not pan the local viewport.

## Research Refresh

- RFC 6143 describes RFB input as pointer movement events sent when the pointer
  moves, and notes that Cursor pseudo-encoding lets a viewer draw the cursor
  locally to improve perceived performance.
- RFC 6143 also keeps framebuffer updates request-driven. Pausing requests is a
  useful local-viewport gesture optimization, but fit-scale trackpad movement is
  ordinary pointer input, not viewport manipulation.

## Change

- Trackpad drags now own viewport interaction only when the current
  `ViewportTransform` is pannable.
- Fit-scale trackpad cursor movement keeps Metal uploads, frame publication, and
  server/local cursor redraws live.
- Zoomed or crop-fill trackpad movement still coalesces streamed frames while
  the local viewport can actually pan with the cursor.

## Verification

- `swift test --filter SessionViewportViewGeometryTests --filter TrackpadModeModelTests --filter PointerGestureResolverTests`
- Result: passed, 45 tests, 0 failures.

## Residual Risk

This targets a concrete stream-continuity regression for trackpad mode. It does
not by itself solve Korean/CJK remote paste confirmation or prove physical
iPhone thermal behavior; those still need device retesting with a signed build.
