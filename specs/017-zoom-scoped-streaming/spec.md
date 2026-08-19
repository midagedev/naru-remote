# Feature Specification: Zoom-Scoped Streaming by Default

**Feature Branch**: `017-zoom-scoped-streaming`
**Created**: 2026-08-19
**Status**: Implemented 2026-08-19. Physical-device poor-network pass residual (founder).
**Product**: Naru Remote
**Input**: Founder question 2026-08-19 — "vnc는 일부 영역만 스트리밍 한다던가 하는건
안되니? 줌인했을때도 전체 화면 다 오는거지? 전송대역폭 최적화 할 방안이 있나 해서."

## Ground Truth

- RFB `FramebufferUpdateRequest` carries an x/y/w/h interest rectangle
  (RFC 6143); a server only reports damage intersecting it.
- Naru already built the whole mechanism for spec 004 FR-017:
  `ViewportRequestRegionPolicy` (64px margin, full-request heartbeat every
  10th request, region rejected when it saves <10% of the framebuffer) wired
  through `RFBFramePump` into `NaruRemoteAppModel`, with the live viewport
  transform published by `SessionViewportView`.
- But D106 gated it to the two opt-in RGB565 stream profiles. **On the
  default profile a zoomed-in session still requested full-framebuffer
  damage** — the founder's question was exactly right.
- Incremental updates carry only damage, so the win is specifically:
  off-viewport damage (scrolling logs, video, animations elsewhere on the
  desktop) no longer rides the cellular link while zoomed in.
- D94's measured failure mode (region requests starving the stream) applied
  to *static center* regions decoupled from the viewport; the shipped policy
  couples the region to the live viewport and keeps the heartbeat.

## Decision (supersedes D106's default, keeps its shape)

D106 held the default back pending more evidence, in the era when this was a
traffic experiment. The founder has now named bandwidth a product goal, and
the remaining unknown — does the real macOS Screen Sharing server honor
region requests under the default encoding preference — is now measured
(below). The promotion is deliberately partial:

- **FR-001**: Every stream profile MUST scope *incremental* framebuffer
  requests to the visible viewport region via the existing
  `ViewportRequestRegionPolicy`. Un-zoomed sessions are unchanged by
  construction: the policy returns nil (full request) when the visible
  region saves under 10%.
- **FR-002**: The power-saver override (user setting or system Low Power
  Mode) MUST keep every request full-frame, unchanged from D106.
- **FR-003**: The *initial* request MUST stay full-frame outside the RGB565
  opt-in lanes — a region-scoped first frame leaves never-delivered area
  unpainted until damage lands there; that glance-startup trade stays where
  D110 measured it. `canUseStartupGlanceScaleMode` keeps keying on the
  opt-in lanes.
- **FR-004**: Staleness of off-viewport content while zoomed MUST stay
  bounded by the policy's full-request heartbeat (every 10th request).
- **FR-005**: No framebuffer dimensions, coordinates, byte counts, pixels,
  or per-sample timings in logs/exports (unchanged privacy rule).

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — `NaruRemoteAppModelTests` | FAIL-first gate flip: default profile sends the visible region on zoomed incremental requests (was `[nil, nil]`); initial request stays full; power saver keeps full requests |
| `swift test` — `ViewportRequestRegionPolicyTests` (existing) | margin, near-full rejection, heartbeat, geometry |
| `swift test` — `LiveMacRFBSmokeTests/testRegionScopedIncrementalRequestsAgainstRealMac` (new, env-gated) | real macOS Screen Sharing, default encoding: every region request delivers or is legitimately held, stream healthy afterwards; per-run in-region/straddling/fully-outside rect counts printed (see corrected ground truth below) |
| Physical iPhone poor-network session (residual, founder) | felt latency/traffic on cellular while zoomed |

## Ground-truth correction (2026-08-20)

The 2026-08-19 live run (quiet screen) measured 0 out-of-region rects; a
2026-08-20 busy-screen run (simulator + test output painting the desktop)
measured **158 out-of-region rects from the same Apple server** — Apple
Screen Sharing does not reliably clip incremental damage to the interest
rectangle under load. Consequences, in order:

- **Correctness is unaffected.** Out-of-region damage applies cleanly to the
  full framebuffer the client keeps; the stream stayed healthy in both runs
  (deliver-or-held 5/5, full-request recovery). The promotion stands.
- **Bandwidth savings against Apple's server are workload-dependent and may
  be zero on a busy screen** — the exact case the region hoped to save.
  Against RFC-clipping servers (TigerVNC family) the saving mechanism is
  real; against Apple the structural bandwidth answer remains helper video.
- The live gate now asserts only the true invariants (deliver-or-held, no
  desync, recovery) and prints in-region/straddling/fully-outside rect
  counts per run, so every future run keeps quantifying actual clipping
  fidelity. The original `outOfRegionRects == 0` assertion encoded one
  day's workload as a contract and was removed with this attribution.

## Residual Risk

- Whether Apple's over-delivery is tile-granular straddling or full region
  ignorance is not yet split under load (the busy-screen run predates the
  straddle/fully-outside split; the gate now prints both — the next busy
  run settles it).
- Third-party servers (TigerVNC, x11vnc, RealVNC) are unmeasured for region
  clipping; RFC-compliant behavior is to clip, and the heartbeat bounds the
  damage if one over-delivers. A server that *under*-delivers (holds
  off-region damage forever) matches the RFC and is exactly what the
  heartbeat exists for.
- Pan/zoom-out can show up to ~10 requests of off-viewport staleness before
  the heartbeat repaints. If the founder perceives it, the follow-on is a
  transform-change-triggered immediate full request (one-line policy hook).
- Bandwidth savings are workload-dependent (large for off-screen video/
  scroll, small for quiet desktops); quantifying on cellular is the
  founder's device pass.
