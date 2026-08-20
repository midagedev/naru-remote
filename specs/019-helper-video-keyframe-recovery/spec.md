# Feature Specification: Helper Video Keyframe Recovery

**Feature Branch**: `019-helper-video-keyframe-recovery`
**Created**: 2026-08-20
**Status**: Implemented 2026-08-20 (grok round + lead review; `swift test`
1659/0 failures, iPhone simulator build green). Real-network device pass
remains under spec 007's existing real-screen residual.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-20 "계속해서 개선해서 출시품질 가자" +
performance research rank-1 lever
(`artifacts/research/2026-08-20-streaming-performance-levers.md`, lever ①:
helper requestKeyframe/stall-recovery wiring). Spec 007 authored the wire
vocabulary; this spec wires the behavior.

## Ground Truth (code-read 2026-08-20)

- The wire vocabulary is fully modeled but **unwired on both ends**:
  `HelperVideoMessageType.requestKeyframe`, `HelperVideoKeyframeRequestBody`,
  and `HelperVideoKeyframeRequestReason`
  (decoderRecovery/startup/userVisibleRecovery) exist in
  `NaruRemote/Sources/NaruRemoteCore/HelperVideo/HelperVideoTransport.swift`.
- The helper **advertises `supportsKeyframeRequest: true`**
  (`NaruHelper/Sources/NaruHelperKit/NaruHelperVideoTransportRequestHandler.swift:232`)
  but has no handler: `NaruHelperVideoStreamNetworkService` reads exactly one
  inbound frame (startStream) and never reads again. The capability is
  currently a false advertisement.
- The app never sends `requestKeyframe`;
  `HelperVideoStreamNetworkClient` treats it as an unexpected *inbound* type
  only.
- App-side failure handling today: a decoder-rejected access unit
  (`.notDisplayable`) or a `streamStalled` frame → **immediate fallback to
  VNC** (`HelperVideoStreamSessionRunner`, `.decoderRejected` /
  `.streamStalled` paths). There is no in-lane recovery.
- The VideoToolbox low-latency stack is **already present** on the live
  paths: the ScreenCaptureKit streaming source encodes with
  `.lowLatencyRealtime` (EnableLowLatencyRateControl + RealTime +
  AllowFrameReordering=false + hardware encoder), so the research lever's VT
  half is done; the missing half is keyframe-on-demand.
- The VT encode loop forces keyframes only by index
  (`index == 0 || index.isMultiple(of: keyFrameInterval)`); there is no
  mid-stream force signal.

## Why

The helper video lane's weakest property is brittleness: a single rejected
access unit abandons the whole lane and drops the user back to VNC pixels
until the next manual re-enable. H.264 recovery after a decode fault needs
exactly one thing — the next IDR — and the encoder can produce one on demand
for the cost of one larger frame. Recovering in-lane keeps the (much
cheaper) video transport alive over the flaky cellular networks the product
is designed for, and makes the advertised capability truthful before the
lane is ever promoted.

## Requirements

- **FR-001 (helper honors requestKeyframe)**: While a stream is active, the
  helper MUST read inbound frames concurrently with sending. An inbound
  `requestKeyframe` envelope whose auth proof validates (same
  `NaruHelperVideoTransportRequestHandler.authorize` contract as
  startStream) MUST cause the **next encoded frame** to be a forced keyframe
  (`kVTEncodeFrameOptionKey_ForceKeyFrame`). Multiple requests arriving
  before the next frame coalesce into one keyframe. Malformed or
  unauthenticated inbound frames are ignored (the stream keeps running);
  inbound message types other than `requestKeyframe` are ignored in v1.
- **FR-002 (signal plumbing, minimal ripple)**: The force signal is a
  per-stream thread-safe object (create file
  `NaruHelperVideoKeyframeRequestSignal.swift` inside
  `NaruHelper/Sources/NaruHelperKit/`) with `request()` and
  `consumePending() -> Bool`. `NaruHelperVideoAccessUnitSource` gains a
  signal-accepting `accessUnitStream(for:keyframeSignal:)` overload with a
  default implementation that ignores the signal, so static/fixture sources
  compile unchanged. Both VideoToolbox sources check
  `consumePending()` per frame in their encode loops. The pipeline creates
  one signal per opened stream and exposes it on
  `NaruHelperVideoOpenedFrameStream`; the network service triggers it.
- **FR-003 (app decoder recovery — pure policy)**: A new pure Core type
  (create file `HelperVideoKeyframeRecoveryPolicy.swift` inside
  `NaruRemote/Sources/NaruRemoteCore/HelperVideo/`) owns the decision table;
  `HelperVideoStreamSessionRunner` consults it instead of falling back
  directly. Table (constants: `maxRecoveryAttemptsPerStream = 2`,
  `recoveryBudgetAccessUnits = 30`):
  - Decoder rejection, `streamDescriptor.supportsKeyframeRequest == false`
    → fallback (today's behavior, byte-identical).
  - Decoder rejection, not recovering, attempts < 2 → increment attempts,
    arm budget (30), emit `.requestKeyframe(.decoderRecovery)`; the runner
    sends it and does NOT fall back.
  - While recovering: every received access unit decrements the budget;
    further decoder rejections are swallowed while budget > 0; a
    **displayable** frame ends recovery (recovered). Budget exhausted
    without a displayable frame → fallback with the existing
    `.decoderRejected` code.
  - Decoder rejection with attempts already at 2 (not recovering) →
    fallback.
- **FR-004 (client send path)**: `HelperVideoStreamNetworkClient` gains a
  way to send a signed `requestKeyframe` envelope on the **live streaming
  connection** (same `HelperVideoAuthProof.make` signing as startStream,
  fresh requestID). Exposed to the runner as an optional
  `@Sendable (HelperVideoKeyframeRequestReason) -> Void` on
  `HelperVideoStreamNetworkEvents`; fire-and-forget (send errors are not
  fatal — the recovery budget already bounds a lost request). Test fakes
  set the closure to record invocations.
- **FR-005 (stall stays terminal in v1)**: `streamStalled` remains an
  immediate fallback. Keyframe recovery targets decode faults only;
  helper-side stalls describe capture/encoder loss where a keyframe request
  cannot help. (Recoverable stalls stay a future contract, per the existing
  comment in the runner.)
- **FR-006 (privacy)**: Reasons and outcomes are fixed catalog labels only.
  No new dynamic content in logs, diagnostics, or exports; no counts of
  bytes/dimensions. Recovery attempts MAY surface later through existing
  fixed-label health states; v1 adds no new diagnostic fields.
- **FR-007 (capability truthfulness)**: After this feature,
  `supportsKeyframeRequest: true` is true for the live helper pipeline. The
  finite/fixture batch path may ignore the signal (default overload); a
  request against it is a harmless no-op and the app's budget produces
  today's fallback.

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — new `HelperVideoKeyframeRecoveryPolicyTests` (Core) | full decision table: no-support → fallback; first rejection → request; swallow-while-recovering; displayable ends recovery; budget exhaustion → fallback; attempt cap 2 |
| `swift test` — `HelperVideoStreamSessionRunnerTests` (**FAIL-first**) | current runner falls back on first rejection without ever calling the keyframe sender; after wiring: sender called once with `.decoderRecovery`, a following displayable keyframe keeps the lane (no fallback), and budget exhaustion still falls back |
| `swift test` — `NaruHelperKitTests` pipeline/signal tests | signal `request()` between frames → next encoded access unit `kind == .keyframe` (VT, macOS); coalescing; default-overload sources unaffected |
| `swift test` — helper service inbound test | authenticated requestKeyframe frame received mid-stream triggers the opened stream's signal; unauthenticated frame does not |
| `swift test` — fake-transport integration | client sends signed requestKeyframe on the live connection; envelope decodes and authorizes on the helper handler |
| iPhone simulator build | app target still builds (no project.yml change expected — no new App-target files) |

## Implementation Notes (2026-08-20)

- Lead review found and closed one implementation defect (FAIL-first in
  `NaruHelperVideoKeyframeRequestTests/testRequestCoincidingWithIntervalKeyframeDoesNotLeakIntoNextFrame`):
  short-circuit evaluation consumed the latch only when the interval had not
  already forced a keyframe, so a request landing on an interval tick leaked
  a redundant forced IDR into the following frame. Fixed by consuming the
  latch unconditionally per frame — a coinciding interval keyframe satisfies
  the request. Proving it required output-gated coordination in the test: a
  wall-clock sleep cannot place a request between two specific frames (VT
  session prepare outlasted 80ms and the request drained at index 1).
- `NaruHelperVideoTransportRequestHandler` needed no edit — its `authorize`
  already accepts signed `requestKeyframe` envelopes; the round added the
  test proving that boundary instead.

## Residual Risk

- Real-network end-to-end (real helper on the Mac + physical iPhone over
  cellular) is not exercised by these gates; the helper lane's existing
  real-screen residual (spec 007, Screen Recording approval) still applies.
- A hostile authenticated peer can request keyframes rapidly (bandwidth
  amplification). Bounded in v1 by coalescing (one forced frame per encoded
  frame at most); an explicit rate cap is deferred until the lane is
  promoted.
