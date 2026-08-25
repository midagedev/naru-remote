# Feature Specification: Every Dropped Frame Names Itself

**Feature Branch**: `028-frame-presentation-ledger`
**Created**: 2026-08-25
**Status**: Implemented 2026-08-25, and it has already returned its first device
answer: **the founder's freeze is not a presentation defect.** On build 8, every
content frame that arrived reached the screen (presented 11 == contentFrameCount
11) and no latch watchdog ever fired; the session was receiving under five content
frames per second with the network read stalled. The investigation moves to the
transport. Original status follows.

**Status (as implemented)**: 2026-08-25. The ledger, both latch watchdogs, the HUD row
and the rewritten gate are in. **The gate does not reproduce the founder's freeze
in the simulator** — against live Screen Sharing it reports 26 presented / 26
pumped, `stalledAt=none`. What is proven is narrower and is stated as such below:
build 7's suspension latch had no release path at all (FAIL-first: 12 frames held
across 6 s, none presented), and that is now bounded. The founder's freeze remains
unattributed; the device HUD is now the instrument that will name it.
**Product**: Naru Remote
**Input**: Founder report on TestFlight build 7 — "프레임 갱신에 문제가 있나봐 갱신이
안되… 앱을 백그라운드로 뒀다가 다시 오면 그때 한 번 되는 거 같다" — followed by the
question that defines this feature: "이런 문제를 명확하게 감사할 방법이 없니?
반복되니까 문제다."

## Why

The founder is right that it repeats. Spec 022 closed "the stream freezes after
the first frame" in build 5. Build 7 froze again, and the investigation was once
more a hand-walk down the render path — which is not an audit, and does not get
cheaper the next time.

The reason it repeats is not that the bugs are subtle. It is that **the only gate
this repository has for the symptom measures the wrong layer.**
`StreamLivenessUnderInteractionUITests` asserts that
`naru.session.perf.contentFrameCount` advances. That counter is incremented by
the frame pump when it decodes a content frame. It says nothing about whether a
single pixel reached the texture. So the entire failure class the founder
actually experiences — *frames keep arriving and the screen does not change* —
is invisible to the gate that exists to catch it. It is a proxy wait: PASS means
"the pump ran", not "the picture updated".

The structural fact underneath is that a frame can disappear silently at six
independent points between the frame store and the texture, and four of them do
not even increment a counter:

| # | Site | Reason it drops the frame | Counted today |
|---|---|---|---|
| 1 | `FramebufferUploadGate.shouldEnqueue` | signature matched the previous frame | no |
| 2 | `MetalFramebufferHostingView.requestRedrawForIncomingFrame` | gesture defers live publication | yes |
| 3 | the same, redraw throttle | throttle said `.deferRedraw` | yes |
| 4 | `MetalFramebufferRenderer.applyPendingStagedUploadIfAllowed` | upload-suspension latch is on and the bypass count is 0 | no |
| 5 | `MetalFramebufferRenderer.applyPendingStagedUpload` | staged storage is `.partial` and the texture size disagrees — the pending frame has already been cleared, so it is lost | no |
| 6 | the staging worker's `MainActor.run` handoff | `stagedUploadGeneration` moved on | no |

Two of the uncounted ones are strong candidates for the build 7 report, and this
spec deliberately does **not** pick between them, because picking by code reading
is what produced the last two wrong attributions in this repository:

- **#4** is a latch with no timeout (`isPendingFramebufferUploadSuspended`, set by
  `beginViewportTransformGesture`, cleared only by `finishViewportTransformGesture`).
  If a gesture ends without the finish path running, presentation stops for the
  rest of the session, and the only frames that get through are the single-shot
  bypasses from `allowNextPendingFramebufferUploadWhileSuspended()`. "Frozen, and
  a trip through the background yields exactly one frame" is the shape that
  produces.
- **#5** was written up here as the second suspect, on the reasoning that it lost
  its self-healing route when spec 026 removed the count-based full upload. **That
  was wrong, and enumerating the texture's mutation sites is what refuted it.**
  In production the texture is only written by `applyPendingStagedUpload` (from
  `draw`) and cleared by `clearFramebuffers`; the direct `applyPendingFramebuffer`
  path is reachable only from the `…ForTesting` helpers. Staging captures
  `requiresTextureRecreation` on the main actor and applies on the main actor with
  no texture mutation in between, so a staged upload can only be `.partial` when
  the sizes already agreed, and nothing can make them disagree before it lands.
  #5 is unreachable, and is kept as a counted defensive branch rather than a
  suspect. Recorded because reading the code was what made it look live — the same
  mistake the rest of this document is about.

Either way the lesson is the same, and it is the one worth building: **a frame
must not be able to vanish without saying who took it.**

## Requirements

- **FR-001** One owner — a frame presentation ledger — accounts for every content
  frame the session frame store publishes. Its invariant is a conservation law:
  `published == presented + Σ(dropped by reason)`.
- **FR-002** Each of the six drop sites records a distinct fixed reason. Adding a
  new early return on the presentation path without a reason must not compile —
  the drop helper returns the ledger's decision type, not a bare `Bool`.
- **FR-003** `presented` is incremented where pixels actually reach the texture
  (`texture.replace` / the blit encoder completing), not where a frame is
  enqueued, staged, or scheduled for redraw.
- **FR-004** Any latch that can gate presentation must self-release. The
  upload-suspension latch gets a watchdog: if presentation has been suspended for
  longer than a bounded interval with frames pending, it releases itself and
  records a distinct reason so the release is visible rather than silent.
- **FR-005** The ledger is published in `SessionStreamStats`, surfaced in the DEBUG
  perf HUD with a stable accessibility identifier per counter, and included in the
  diagnostic export.
- **FR-006** Constitution §IV: counts and fixed reason labels only. No coordinates,
  no framebuffer dimensions, no byte counts, no per-frame timings, no user content.
- **FR-007** The liveness gate is rewritten to assert the **presented** counter,
  not `contentFrameCount`, and additionally asserts the conservation law holds at
  the end of the run. The old assertion stays only as a precondition ("the pump is
  alive"), never as the liveness property.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — ledger unit tests | the conservation law holds across every drop reason, including simultaneous ones | direct |
| `swift test` — `MetalFramebufferRendererTests` | a suspended renderer with a pending frame records reason #4 and presents nothing; one bypass presents exactly one frame | FAIL-first: today it records nothing |
| `swift test` — staged-upload size-mismatch test | reason #5 is recorded and the frame is not silently lost | FAIL-first |
| `swift test` — latch watchdog test | a latch held past the bound releases itself and says so | FAIL-first |
| iPhone simulator E2E — rewritten `StreamLivenessUnderInteractionUITests` | the *presented* counter advances through zoom, pan and dock; conservation holds | **FAIL-first is the acceptance bar for this whole spec**: it must go red against build 7's behaviour before it is trusted |
| Physical iPhone, build 8 | the founder's own freeze reproduces with a named reason on screen | founder device pass |

## What The First Live Runs Actually Found — Two Instruments, Not Two Defects

The rewritten gate went red twice before it went green, and **both reds were
defects in this spec's own instrumentation.** Recorded because the pattern is the
whole reason this feature exists, and because a spec that reports only its final
green is the kind of document that lets the next one through.

| Run | Reported | Actually |
|---|---|---|
| 1 | red, `held by: superseded`, presented 25 / pumped 31 | The ledger was published upward once every 15 incoming frames. The run carried 31 frames total, so the HUD updated about twice and the gate asserted on a counter that had not been pushed yet. Fixed: report on change. |
| 2 | red, `held by: heldByThrottle`, presented 33 / pumped 35 | The assertion was absolute — "presented must advance within 20 s". A quiet remote produces no frames to present, so a healthy session reddens. Fixed: assert presentation **relative** to the pump, and report a quiet window as inconclusive rather than passing it silently. |
| 3 | **green**, presented 26 / pumped 26, `stalledAt=none quietAt=none` | Presentation kept up exactly. |

So the acceptance bar written above — "it must go red against build 7's
behaviour" — **is not met, and the spec is not claiming it is.** The gate measures
the right layer now and passes on a healthy session; it did not reproduce the
founder's freeze. Simulator plus loopback Screen Sharing may simply not be where
that freeze lives. What the gate buys is that this failure class can now redden a
gate at all, which was not previously true at any layer.

The one defect proven by measurement is the unbounded suspension latch, and it was
proven at the unit layer against build 7's exact source: suspended, twelve frames
enqueued over six seconds, zero presented, no release path. That is fixed.

## The First Device Export — Presentation Was Never The Problem

Build 8, founder's iPhone, a real tailnet profile (`profileHostKind: magicDNS`),
exported while the picture was not updating:

| | |
|---|---|
| `framePresentationPresentedCount` | 11 |
| `contentFrameCount` | 11 |
| `rendererUploadSampleCount` | 11 |
| `framePresentationWatchdogReleaseCount` | **0** |

**Every content frame that arrived reached the screen.** No latch was ever stuck —
the watchdogs never fired. The suspension-latch hypothesis this spec was built
around is refuted on the device, and the freeze is not a presentation defect at
all. What the same export shows instead:

| | |
|---|---|
| `contentFrameCount` | 11, over `overTenSeconds` |
| `contentFramesPerSecondBucket` | `underFive` |
| `emptyUpdatePermille` | 558 |
| `transportIdleTimeoutCount` | 8 |
| `averageNetworkReadTimingBucket` | `stalled` |
| `averageReceiveTotalTimingBucket` | `stalled` |

The screen is not updating because the server is barely sending anything. The
17 fps measured against loopback Screen Sharing (spec 027) does not survive the
trip over a real tailnet, and **every frame-rate number in this repository was
taken on loopback.** That is the next investigation, and it belongs to the
transport, not the renderer.

Two further things the export settles:

- `dirtyRectangleCountMax` is **1488** on the founder's Mac. Spec 026 set
  `quadraticMergeInputCeiling = 1024` on the basis that real damage counts peaked
  at 738 — measured on loopback with a synthetic stimulus. The real peak is
  double that, so the blunt linear pre-reduction is running in production, which
  spec 026 described as "the backstop for counts no server has been observed to
  send". It has now been observed. `rendererFullUploadCount` is still only 1
  (91 permille), so this is a note, not a regression.
- The ledger's own `publishedCount` read **568 against 11 content frames** — see
  below. The instrument was counting SwiftUI view rebuilds as publications.

### The Fifth Instrument Defect

`recordPublishedFrame()` sat in `Coordinator.enqueue`, which SwiftUI calls from
`updateUIView` on *any* state change — zoom, cursor movement, dock — not only when
a frame arrives. So `publishedCount` counted view rebuilds, and
`framePresentationPresentedPermille` reported **19 permille**: a number that says
98% of frames never reach the screen, in a session where presentation was keeping
up perfectly. Left alone it would have sent the next round after the renderer,
which is exactly the wrong direction and exactly what this ledger exists to
prevent.

Fixed by making the frame store the authority on what was published: view-update
enqueues are now unaccounted on both sides of the books, so the ledger cannot be
inflated by SwiftUI. Pinned by `testAnUnaccountedEnqueueDoesNotMoveTheBooks`.

Counting the tally honestly: five instrument defects across specs 025–028, four of
them found only because something downstream refused to agree with them. The
ledger's value here was not that it named the culprit — its first reading named
the wrong one — but that `presented == contentFrameCount` was checkable at all,
which ruled the renderer out in a single export instead of another week of
reading code.

## Non-Goals

- Attributing the founder's freeze to a specific site. This spec builds the
  instrument that names it; the attribution belongs to whatever the ledger reports
  from a real session, not to the code reading that opened this document. Bounding
  the latches (FR-004) is in scope and is not an attribution — an unbounded latch
  on the presentation path is a defect whether or not it is *this* defect.
- Removing drop sites. Several are legitimate (a duplicate frame should be
  dropped; a gesture should get touch priority). The requirement is that they are
  named and counted, not that they disappear.

## Residual Risk

- The conservation law is only as good as the definition of "published". If the
  frame store itself drops a frame upstream, this ledger reports a consistent set
  of books over an already-short count. Extending it upstream into the pump is
  deliberately out of scope, and this boundary is stated rather than closed.
- A ledger adds a counter increment on the hot presentation path. It is counts
  only, no timing and no allocation, but the claim that it is free is an
  expectation until measured — the release benchmark (spec 025) is the instrument
  that must confirm it, and this spec is not complete until that reading exists.
- The watchdog bound in FR-004 is a judgement, not a measurement. Set too short it
  fights a legitimate long gesture; too long it leaves the founder staring at a
  frozen screen. It errs toward releasing, because a stale picture during a pinch
  is a smaller failure than a dead session.
- The rewritten gate needs the perf HUD, which is DEBUG-only. A Release build the
  founder installs from TestFlight therefore cannot show the ledger on screen. The
  diagnostic export path in FR-005 is what covers that case, and it must be
  verified on a Release build, not assumed from the DEBUG surface.
