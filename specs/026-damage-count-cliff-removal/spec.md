# Feature Specification: No Damage-Count Cliff To A Full Upload

**Feature Branch**: `026-damage-count-cliff-removal`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21 (count cliff removed; full uploads 174‰ → 0‰
under a controlled live stimulus with the damage distribution held identical).
Device confirmation pending.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-21 — "실용적인 수준까지 쭉 밀어봐" — and the
release-built re-measurement that spec 025 made possible.

## Why

Spec 024 removed a rectangle-count cliff at 64 by merging damage instead of
re-uploading the framebuffer, and put a new ceiling at 512 above which merging
is skipped and the frame takes a full upload. The stated reason was that a frame
arriving with that many rectangles "has changed enough that one full upload is
the cheaper answer". That was an assumption, and it is wrong for this server.

Measured live against real Screen Sharing with a 30 Hz stimulus, eight 15 s runs
(release build, per spec 025):

| | value |
|---|---|
| damage rectangle count, median frame | 3 |
| damage rectangle count, p95 | 690–713 |
| damage rectangle count, peak | 738 |
| damage **area** on those high-count frames | 337–385‰ (34–39%) |
| full uploads, median of eight runs | **174‰** |

The distribution is bimodal, not heavy-tailed: half the frames carry 3
rectangles, and the top few percent carry ~713. Those high-count frames changed
roughly a third of the screen — comfortably inside
`maximumPartialUploadAreaFraction` (60%) — and were re-uploading all of it
because of how many messages the change arrived in.

The branch was confirmed by intervention, not by reading: lifting only the
ceiling in a scratch build, under an identical stimulus with the same measured
damage distribution, took full uploads from 174‰ to 0‰.

The structural lesson is that a **count** was never the right axis. Spec 024 set
the cliff at 64, this spec's measurement found the replacement at 512 sits below
the server's working range, and any fixed count picked from one stimulus will do
the same thing again. A bound that degrades to the most expensive possible
upload is not a safety valve. Damage *area* already identifies a genuine
repaint, and it is the only thing that should send a frame down the full-upload
path.

## Requirements

- **FR-001** No rectangle count sends a frame to a full upload. Only damage
  area, absent damage, and texture recreation do.
- **FR-002** The merge cost stays bounded for any incoming rectangle count: above
  `quadraticMergeInputCeiling`, a linear pass unions consecutive raster-order
  runs down to that ceiling before the quality-aware merge runs.
- **FR-003** The pre-reduction ceiling sits above the observed working range.
  It is 1024 against a measured peak of 738, because the linear pass is blunt —
  measured live, a ceiling of 256 inflated merged area past the area rule and
  left 57‰ of content frames on the full-upload path where letting the
  quality-aware merge see all ~713 rectangles left 0‰.
- **FR-004** Merging never turns a frame that qualifies for a partial upload into
  one that fails the area rule.
- **FR-005** Every region set still covers every original rectangle, including
  after pre-reduction, so a partial upload cannot leave a damaged pixel stale.
- **FR-006** The per-frame merge is cheap at the counts it actually runs on. The
  neighbour costs are cached and patched on each merge instead of recomputed for
  the whole array, since a merge only changes the two costs adjacent to it.
- **FR-007** Constitution §IV: no dimension, coordinate, or rectangle content is
  logged, exported, or printed.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — `testHighRectangleCountStillMergesInsteadOfFallingBackToFullUpload` | the measured live shape (713 rectangles, ~40% area) takes the partial path | FAIL-first: `("full") is not equal to ("partial")` with the 512 bail restored |
| `swift test` — `testMergingDoesNotInflateAPartialEligibleFrameIntoAFullUpload` | the pre-reduction cannot push a partial-eligible frame over the area rule | pins the regression a 256 ceiling caused |
| `swift test` — `testRasterRunReductionCoversEveryRectangleItReplaces` | 2000 rectangles reduce to ≤ 64 regions with nothing dropped | FAIL-first: `("2000") is greater than ("64")` |
| `swift test` — `testWorstCaseMergeStaysWithinAPerFrameBudget` | 8192 rectangles stay inside a per-frame budget | FAIL-first: `("8192") is greater than ("64")` |
| Live Mac + controlled 30 Hz stimulus | full uploads 174‰ → 0‰ with rectangle count and damage area held identical | `VNCLiveBenchmark`, release |
| Founder device (iPhone) | the win this Mac cannot show — upload bandwidth, power, thermals | device pass |

Measured merge cost per frame, release build: 0.33 ms at the live peak (738
rectangles), 0.65 ms at the ceiling, and bounded there for any larger count.
Cost caching took the live-peak case down from 1.2 ms.

## What This Does Not Fix

Frame rate, again. Content fps across the three post-fix runs was 4.5 / 10.2 /
6.2 against a pre-fix range of 5.3–10.9 — no movement outside run-to-run noise,
for the same reason spec 024 gave: a desktop GPU absorbs a full texture upload
cheaply. The expected win is on the phone, and it is still **inferred, not
measured**.

Nor does it touch the two things that actually dominate the founder's
experience:

- Picture staleness. The visual-freshness marker reads a median of ~0.9–1.3 s of
  age with a p95 of 7–13 s, while update latency averages 31 ms. Whatever
  produces that gap is untouched here, and the metric is bimodal across
  otherwise identical runs (three of sixteen runs read ~210–265 ms average),
  which makes it a candidate for its own instrument audit before it is trusted
  as a target.
- The transport. Helper video measured `frameRateBucket: upTo30`,
  `sustainedUpdateBand: smooth`, `decodePressure: low` on the Mac side with
  Screen Recording already granted (spec 007). The remaining blocker is physical
  iPhone pairing (spec 010 T014), which needs the founder.

## Residual Risk

- `quadraticMergeInputCeiling` (1024) is now the only count-shaped constant
  left, and it is chosen from one server's observed range. A server that sends
  more than 1024 rectangles per frame gets the blunt linear pass, which may
  inflate area enough to trigger a full upload — the same failure mode as
  before, one order of magnitude further out. It no longer *guarantees* a full
  upload, which is the difference that matters.
- Merging still trusts the server's damage rectangles exactly as the partial
  path always has. A server that under-reports damage now leaves stale pixels in
  more places, because more frames take the partial path.
