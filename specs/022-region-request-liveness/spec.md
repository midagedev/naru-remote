# Feature Specification: Region-Scoped Request Liveness

**Feature Branch**: `022-region-request-liveness`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21 (pump parked-set fix + region-aware fake +
liveness gates; `swift test` 1691/0 failures, live gates green). Founder
device re-test pending on build 5.
**Product**: Naru Remote
**Input**: Founder bug report 2026-08-21 — "퍼스트프레임은 잘 오는데 그 이후
조작할때 다음 프레임이 안오는 상태야" (build 4 on device), followed by
"이걸 왜 네가 시뮬레이터 테스트로 못잡았을까 개선지점이네".

## The Defect

`RFBFramePump`'s pipelined request/response branch keeps
`requestPipelineDepth` (production: 3) incremental `FramebufferUpdateRequest`
messages parked on the server and — before this fix — refilled **only after
a consumed response**. Each parked request carries the viewport region that
was current when it was sent, and RFB answers a request only with damage
**inside its own region**.

So when the visible region changed (a pan, a zoom, or the input dock /
soft keyboard shrinking the visible area, which is what makes spec 017's
region scoping kick in at all), every parked request described an area the
user had already left. Damage in the new viewport could not satisfy them,
no response was consumed, no refill happened, and the every-10th full-frame
heartbeat — keyed on delivered-frame count — could never advance. The
session deadlocked permanently after the first frame.

Live-measured on real Screen Sharing before the fix: with damage driven
outside the parked region, **7 of 8 receives were held** and the stream only
recovered when a full-frame request was issued by hand.

## Why The Gates Missed It (the founder's second question)

1. **The fakes had no region semantics.** `FakePipelinedFramebufferUpdateSource`
   and the `FakeRFBServer` transcript fixtures answer whatever is queued
   regardless of the region in the request. A fake that ignores a parameter
   cannot fail on misuse of that parameter, so parking a stale region was
   free in every unit and simulator gate.
2. **No gate moved the viewport mid-stream.** Spec 017's live gate held the
   region fixed and only counted deliver-or-held; spec 018's probe used a
   serial *non-incremental* request loop — a different code path from the
   shipping pump, so it could not see pipelining at all.
3. **No gate asserted the invariant the user feels.** Everything measured
   mechanism (request counts, extent ratios, rect classification); nothing
   asserted "frames keep arriving while interacting".

## Requirements

- **FR-001 (parked-set single owner)**: The pipelined branch owns both how
  many requests are outstanding **and which region they describe**
  (`pipelinedParkedRegion`). Region is part of the parked-set identity, not
  metadata.
- **FR-002 (re-park on viewport change)**: When the current region differs
  from the parked region, park one request for the new region immediately
  instead of waiting for a response that may never come. Capped at
  2 × depth so a continuous pinch cannot flood the server.
- **FR-003 (widen on hold)**: An idle timeout while a region is parked
  widens to a full-frame request. A client cannot distinguish "nothing
  changed anywhere" from "changes are outside my region", and the cost
  asymmetry is total: a held region deadlocks the session, while a
  full-frame incremental request on a genuinely quiet screen simply holds
  too — zero bandwidth.
- **FR-004 (observability)**: `pipelinedRegionWidenedRequestCount` exposes
  starvation pressure as a count (constitution §IV: no regions, no
  coordinates). Non-zero means the requested area and the actual damage are
  diverging — previously that state was visible only as a frozen screen.
- **FR-005 (region-aware fake)**: The Core test suite gains
  `FakeRegionAwarePipelinedSource`, which holds a request unless the pending
  damage intersects that request's region. This is the missing gate
  primitive: it turns a live-only, device-only failure into a 0.2 s
  deterministic one.
- **FR-006 (liveness gates)**: Both levels assert the user-facing invariant:
  a deterministic pan test (region and damage both move) and a live
  pump-driven gate (damage outside the request region) must keep delivering
  frames.

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — `RFBFramePumpTests/testStreamStaysLiveWhenAPanMovesBothTheRegionAndTheDamage` (**FAIL-first**) | pre-fix logic delivers **0** content frames after a pan (the founder's symptom, reproduced deterministically); post-fix frames flow |
| `swift test` — `RFBFramePumpTests/testHeldPipelinedRegionRequestWidensToFullFrameRequest` (**FAIL-first**) | a held region request widens to full-frame, and the widen is observable via the counter |
| `swift test` — existing pipelined depth/idle tests | the depth and no-growth contracts still hold for region-free streams (byte-identical behavior) |
| Live — `LiveMacRFBSmokeTests/testPumpKeepsDeliveringWhenLiveDamageIsOutsideTheRequestRegion` | the shipping pump keeps streaming against real Screen Sharing while damage lands outside its region |
| Live — `LiveMacRFBSmokeTests/testPipelinedRegionRequestsDoNotStarveWhenDamageMovesOutsideTheRegion` | server ground truth: out-of-region damage is held (measured 1/8 answered), and a full request recovers |
| Live — `LiveMacRFBSmokeTests/testPipelinedIncrementalStreamSurvivesAppleScaleFactorMidFlight` | refutes the first hypothesis: a mid-flight spec-018 ScaleFactor does **not** break the pipelined stream (12/12 answered, resize announced) |
| Simulator E2E — `StreamLivenessUnderInteractionUITests` (**FAIL-first**) | the whole product path: real app in the iPhone simulator against live Screen Sharing, zoom → pan → dock open, asserting the HUD frame counter advances. Neutralizing the fix fails it at "after panning" and "after the dock opened"; with the fix `stalledAt=none` |

## Residual Risk

- `FakeRFBServer`'s transcript fixtures still lack region semantics; the new
  Core fake covers the pump and the simulator E2E gate covers the product
  path against a real server, so the remaining gap is a hermetic app-model
  variant (nice-to-have, not a blocker).
- `ViewportRequestRegionPolicy.fullFallbackTimeoutStreak` remains unfed by
  production (the pump now owns escalation, deliberately one owner); the
  parameter stays for benchmark callers.
