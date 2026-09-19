# Spec 045 — the drawn trackpad cursor's tip lands on the pixel it addresses

**Status:** Implemented 2026-09-19 — founder device pass (SC-1) open.
Successor to spec 044, which closed the *picture* half of the founder's
misalignment report and left this half open.

## The report

Founder, 2026-09-19, physical iPhone, helper-video session in trackpad mode:
"여전히 마우스 커서가 살짝 어긋나 균일하게 살짝 오른쪽에 보이네", then, on
being asked: the cursor in the video sits to the **right** of the one the app
draws, the gap **shrinks** as the viewport zooms in, and a plain VNC session is
accurate. Asked about the drawn cursor being oversized, the founder ruled it
out of scope: "커서 큰거는 괜찮은것 같아".

Spec 044 had just shipped (build 21) and fixed a different defect in the same
report — `layer.frame = bounds` on a layer already carrying the viewport
transform, which drew the helper's video unzoomed and displaced. That one is
closed. What the founder is seeing now is a second, much smaller offset that
survived it.

## Measurements

Screenshots `IMG_6665.PNG` / `IMG_6666.PNG` (1290 px wide, iPhone at 3× — so
**1 view point = 3 image pixels**), both a helper-video session in trackpad
mode, both showing the two cursors. Each cursor's tip was located by
thresholding: the app's glyph is a hard-edged near-white silhouette, the remote
pointer is a soft dark arrow in the video.

| Shot | Zoom | `displayScale` | Drawn tip (px) | Remote tip (px) | Offset |
| --- | --- | --- | --- | --- | --- |
| IMG_6665 | fit (1×) | 0.142 | (1019, 374) | (1045, 374) | **+26 px = +8.7 pt, 0 pt** |
| IMG_6666 | max (≈4×) | ≈0.57 | (642, 766) | (666, 769) | **+24 px = +8.0 pt, +1.0 pt** |

`displayScale` was read off the two cursors' own heights: the drawn glyph is 63
and 65 px in the two shots (constant, because `visualScale` is clamped at 1),
the remote pointer 9 and 41 px, and the ratio is `displayScale`.

**The offset does not scale with zoom.** A four-fold change in `displayScale`
moved it from 8.7 pt to 8.0 pt. An error in framebuffer coordinates would have
grown four-fold; this is a constant in **view points**, which is also why the
founder perceives it shrinking as the content grows around it.

Two facts ruled the rest out before this spec was written:

- The video and the cursor overlay share the *same* horizontal mapping. Both
  aspect-fit a width-limited desktop into the same container and are then
  scaled about the container centre: the cursor overlay's content origin is
  `(viewSize − contentSize)/2 + panOffset`, and the layer's is the same
  expression. A pillarbox or aspect mismatch therefore cannot displace them
  horizontally at all, only vertically, and only by tenths of a point.
- The helper's capture is clean. Measured on the founder's Mac with the
  helper's own `SCStreamConfiguration`: `contentRect` leaves a symmetric
  1.15 px pillarbox in the 960-wide bucket and none in the 1512-wide one, and
  differencing a `showsCursor: true` frame against a `showsCursor: false` one
  puts the baked pointer within about a point of where the window server says
  it is, at both capture scales.

## Requirements

- **FR-001** — The tip of the cursor the app draws in trackpad mode lands on
  `ViewportTransform.viewPoint(fromFramebufferPoint:)` of the pointer position
  it is drawing, within 1 view point, at every zoom.
- **FR-002** — FR-001 holds for both render branches: the RFB server cursor
  shape, and the local fallback glyph used when the server has sent none.
- **FR-003** — The tip's placement is measured from the *rendered* view, not
  restated from the arithmetic that placed it. A gate that asks the placement
  code where it put the tip cannot see this defect.
- **FR-004** — `visualScale = max(1, displayScale)` is out of scope. The drawn
  cursor stays the size it is; the founder has looked at it and accepted it.
  Changing it is a separate decision, not part of closing this.

## Success criteria

- **SC-1** — On the founder's device, in a helper-video trackpad session, the
  drawn cursor's tip sits on the remote pointer's tip, at fit zoom and zoomed
  in.
- **SC-2** — A gate fails on the unmodified source and passes after the fix.
- **SC-3** — Plain VNC sessions are unchanged: clicks still land where the
  drawn tip points.

## Root cause and fix

`TrackpadCursorGlyph.measureTipOffsetFromCenter` scanned its alpha buffer
bottom-first — `row = height - 1 - y` — on the belief that a `CGContext`'s
bottom-left origin also reverses the buffer's row order. It does not: drawing a
CGImage into a same-size alpha context leaves memory row 0 holding the
displayed top row. Verified independently on 2026-09-19 with a four-row probe
whose only opaque row was the top one; it came back in memory row 0.

So the scan answered with the leftmost pixel of the glyph's *bottom* row — the
tail — instead of the tip, and returned `tipOffsetFromCenter = (+2.67, −11.33)`
where the truth is `(−5.33, −10.33)`. Both render paths place the glyph box by
subtracting that vector from the anchor, so the box, and the drawn tip with it,
sat **8.0 pt to the left** and 1.0 pt off vertically — at every zoom, because
the vector is a constant in view points. That is the founder's +8.7 pt / +8.0 pt
to within a third of a point, arrived at from the opposite direction.

The tell that this was the fallback branch and not the RFB server cursor is in
the founder's own screenshots: the drawn arrow is a solid near-white silhouette
with no black outline. A macOS server cursor bitmap has one.

The fix removes the flip. Nothing else changed: the server-cursor branch was
measured as a control and was already exact, and `visualScale` is untouched
(FR-004). `findings.md` in this directory carries the full measurement record.

## Verification

- `NaruRemote/Tests/NaruRemoteBenchmarkTests/TrackpadCursorApexAlignmentTests.swift`
  renders the real host view to a bitmap and finds the tip by scanning those
  pixels, never by asking the placement code (FR-003). FAIL-first, run by the
  lead against the reverted source: Δx −8.17 and −8.50 at zoom 1, −8.17 and
  −7.92 at zoom 4, Δy under 1 pt everywhere, with the server-cursor branch
  staying green. Post-fix: 5 tests, 0 failures.
- `swift test` — 1959 tests, 0 failures.

## Out of scope

- The drawn cursor's size (FR-004).
- The helper capturing only the main display while the RFB framebuffer is the
  union of all attached displays — recorded in `NEXT_STEPS.md` 00p.
- Apple Screen Sharing intermittently dropping pointer moves.
