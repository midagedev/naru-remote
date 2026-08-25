# Feature Specification: Stop Scoping Incremental Requests To The Viewport

**Feature Branch**: `030-full-frame-incremental-requests`
**Created**: 2026-08-25
**Status**: Drafted 2026-08-25.
**Product**: Naru Remote
**Input**: The founder's build 8 session ran at under five content frames per
second. Spec 028 proved the renderer was presenting everything it received;
spec 029 proved the network was a 212 ms additive term and not the constraint.
This is what was left.

## Why

Isolating one axis at a time against live Apple Screen Sharing, release build,
`--network-condition none`, identical stimulus and profile, the request region is
the only axis that moves the result:

| axis changed | content fps | avg update | p95 update |
|---|---|---|---|
| baseline (viewport-scoped request) | 0.83 | 783 ms | 5159 ms |
| client-pressure pacing off | 0.75 | 514 ms | 5025 ms |
| empty-update backoff off | 0.74 | 647 ms | 5177 ms |
| stimulus 12 Hz → 30 Hz | 1.00 | 499 ms | 5022 ms |
| **request region → full framebuffer** | **5.91** | **34 ms** | **126 ms** |

Repeated three times, the two arms do not overlap:

| | viewport-scoped | full framebuffer |
|---|---|---|
| content fps | 0.74 / 0.49 / 0.67 | 5.66 / 6.25 / 7.08 |
| avg update | 787 / 637 / 540 ms | 33 / 33 / 33 ms |
| p95 update | ~5100 ms | 119–133 ms |

**Asking Apple Screen Sharing for a viewport-scoped rectangle makes it answer
roughly twenty times slower than asking for the whole framebuffer**, with a p95
that sits at the client's idle timeout — the server frequently does not answer a
region request at all until something forces it.

This is not new information so much as the completion of it. Commit `09f28915`
already recorded, as a correction to spec 017's ground truth, that "Apple does not
reliably clip region requests under load". What was missing was the price, and the
price is the founder's entire frame rate.

### The obvious alternative explanation, tested and rejected

A p95 of ~5150 ms against a 5 s idle timeout is exactly what a region that never
changes would produce, and the benchmark's phone-portrait region is a centred
crop while the stimulus window sits at the top left. If they did not overlap, the
whole finding would be an artefact of the harness.

Re-run with the stimulus moved to the centre of the screen, inside the region:

| stimulus placement | viewport-scoped | full framebuffer |
|---|---|---|
| top-left | 1.08 fps / 741 ms | 5.42 fps / 36 ms |
| centred | 0.83 fps / 689 ms | 3.82 fps / 50 ms |

The gap survives. The region overlaps the changing content and the server is
still an order of magnitude slower to answer it.

### Who is affected

`usesViewportAwareRequestRegions` is true for every session that is not in power
saver or iOS Low Data Mode, and the policy emits a region whenever the visible
area saves at least 10% of the framebuffer. An iPhone showing a wide desktop is
always looking at a crop, so **this is the normal path, not the zoomed-in edge
case.** The founder's export reports `viewerStreamPowerMode: balanced`.

## Requirements

- **FR-001** Incremental framebuffer update requests are full-frame by default.
  The viewport-scoped path is retained but no longer the default, because the
  measurement above is one server family on one machine and reversing course
  should not require rebuilding the machinery.
- **FR-002** The *initial* request keeps its current behaviour. It is gated
  separately today (`usesViewportAwareInitialRequestRegion`, RGB565 lanes only)
  and nothing here was measured about it, so it is not changed by inference.
- **FR-003** A test pins that a normal session requests full-frame incrementals,
  failing against the current default.
- **FR-004** The benchmark keeps both arms so the decision stays re-measurable,
  and the numbers above are recorded with the condition, build configuration and
  server they were taken under.
- **FR-005** Constitution §IV: no coordinates or framebuffer dimensions in logs,
  exports or test output. The region geometry stays in memory as it does today.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — request-region default test | a balanced-power session asks for the full framebuffer | FAIL-first against today's default |
| Live Mac, release, viewport vs full, 3 repeats | the gap, and that it is not the stimulus placement | done — recorded above |
| Founder device, build 9 export | `contentFramesPerSecond` leaves `underFive`; `framePresentationPresentedCount` still tracks `contentFrameCount` | founder device pass |

## Non-Goals

- Removing the viewport-scoped machinery. It stays, off by default, and spec 017's
  bandwidth argument for it is untested rather than refuted — no one has measured
  what full-frame incrementals cost on a metered link. That measurement is worth
  making; it is not worth blocking a twentyfold frame-rate defect on.
- The `requestPipelineDepth` constant. Spec 029 measured it as making no
  difference and it is unchanged.
- Explaining *why* Apple answers region requests so slowly. The product decision
  does not depend on the mechanism, and guessing at it is how the last three
  rounds went wrong.

## Residual Risk

- One server family (Apple Screen Sharing), one machine, loopback. Other RFB
  servers may handle region requests well, which is part of why FR-001 keeps the
  path rather than deleting it.
- Full-frame incremental requests send more damage per response on a busy screen.
  On the founder's link that is a trade of bandwidth for latency, and only the
  latency half is measured. The device export's `dirtyAreaPermille` and
  `changedPixelsPermille` are the instruments to watch for the other half.
- The measurement was taken with the viewport at a phone-portrait crop. A session
  zoomed much further in would save far more area, and the trade could look
  different there. Untested.
