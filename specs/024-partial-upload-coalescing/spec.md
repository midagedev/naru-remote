# Feature Specification: Partial Upload Coalescing

**Feature Branch**: `024-partial-upload-coalescing`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21 (region merge + single-owner region list;
full uploads 200‰ → 0‰ under a controlled live stimulus, `full-upload-failed`
cleared). Device confirmation pending.
**Product**: Naru Remote
**Input**: Founder report 2026-08-21 — "트랙패드 잘 되는데 이게 왜 이렇게 반응이
느리지" — and the measurement that followed.

## Why

The founder's slowness is **not** the input path: measured on a live session,
outbound pointer events cost `0 / 0 ms` queue and operation time. What lags is
the picture — the server produces only **9.4 content fps** even with every
client pacing floor removed (`--stream-shape-client-pressure off
--stream-shape-frame-interval 0` on loopback), so ~10 fps is Apple Screen
Sharing's own cadence ceiling in request/response mode. Trackpad mode did not
make anything slower; it made that ceiling visible, because the locally drawn
cursor moves at display rate while the picture under it does not.

Inside that ceiling, the benchmark named one client-side defect as its
**primary** issue: `full-upload-failed` → `rendererUpload` →
`inspectLocalRenderPipeline`. `FramebufferUploadPlan.plan` fell back to
re-uploading the entire framebuffer whenever the server sent more than
`maximumPartialUploadRegionCount` (64) damage rectangles — regardless of how
little had actually changed.

Live-measured against real Screen Sharing under a controlled 12 Hz stimulus
(`VNCLiveStimulusWindow`), with the identical damage distribution in both arms:

| | rect count avg/p95/max | damage area avg/max | partial/full uploads | practical target |
|---|---|---|---|---|
| before | 9 / 112 / 112 | 5‰ / 68‰ | 15 / **3** | **fail** (`full-upload-failed`) |
| after | 9 / 112 / 112 | 5‰ / 68‰ | **19 / 0** | warning (issue cleared) |

So frames that changed **0.5% of the screen on average** were re-uploading
100% of it, purely because the change arrived as 112 small rectangles instead
of 64. A terminal scrolling text is exactly that shape.

The branch was identified by intervention, not by reading: raising the cap in a
scratch build cleared `full-upload-failed` under an otherwise identical
stimulus, which rules out the other two full-upload branches (missing damage,
damage area over 60%).

## Requirements

- **FR-001** When valid damage rectangles outnumber
  `maximumPartialUploadRegionCount`, they are **merged** down to that count
  rather than abandoning the partial upload.
- **FR-002** The merged set covers every original rectangle, so a partial
  upload can never leave a damaged pixel stale.
- **FR-003** Merging always takes the cheapest available merge (least added
  area) so same-line neighbours join before distant damage is bridged.
- **FR-004** The genuine escape hatches stay: a frame whose *merged* damage
  exceeds the area rules, a frame with no usable damage, and a texture
  recreation all still take one full upload.
- **FR-005** The merge is at worst quadratic in the rectangle count, and is
  skipped entirely above `maximumCoalescingInputCount` (512) — it runs on every
  content frame, so an all-pairs (cubic) merge would cost more than the upload
  it avoids.
- **FR-006** Single owner: `FramebufferUploadPlan.uploadRegions` is the one
  place the region list is produced. `plan` counts those regions and the
  renderer uploads exactly those, so the reported region count and the work
  done cannot disagree.
- **FR-007** Constitution §IV: no dimension, coordinate, or rectangle content
  is logged, exported, or printed by any of this.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — `FramebufferUploadPlanTests` | merge under the cap, full coverage of originals, distant damage not bridged, area/no-damage/absurd-count fallbacks intact | FAIL-first against the pre-merge plan |
| `swift test` — `FramebufferUploadPlanTests` complexity gate | worst-case (512-rect) merge inside a per-frame budget | catches a return to all-pairs greedy |
| `swift test` — `MetalFramebufferRendererTests` | the renderer uploads the merged regions: damaged pixels refresh, undamaged pixels are left alone | real Metal texture readback |
| Live Mac + controlled 12 Hz stimulus | full uploads 200‰ → 0‰ with the damage distribution held identical | `VNCLiveBenchmark` |
| Founder device (iPhone) | the win that this Mac cannot show — texture-upload bandwidth, power, thermals | device pass |

## What This Does Not Fix

Frame rate. On this Mac the eliminated full uploads did not move content fps
(6.8 → 7.5, inside run-to-run noise) or decode time, because a desktop GPU
absorbs a 1512×982 texture upload cheaply. The expected win is on the phone —
bandwidth, memory traffic, power and thermals from re-uploading a full texture
on a fifth of all frames — and that is **inferred here, not measured**.

The ~10 fps ceiling is the server's, and no client change moves it. The
measured answer to it is the helper video transport: the same day, real
ScreenCaptureKit capture reported `frameRateBucket: upTo30`,
`sustainedUpdateBand: smooth`, `decodePressure: low`, verdict `pass` (spec 007).

## Residual Risk

- Merging trusts the server's damage rectangles exactly as the existing partial
  path already does. A server that under-reports damage would leave stale
  pixels in more places than before, because more frames now take the partial
  path.
- `maximumPartialUploadRegionCount` (64) is now a *merge target* as well as a
  cap, so it silently sets how coarse the merged regions get. A future change to
  it changes upload granularity, not just a fallback threshold.
