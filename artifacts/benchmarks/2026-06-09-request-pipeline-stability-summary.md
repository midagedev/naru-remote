# Request Pipeline Stability Summary — 2026-06-09

## Scope

Add a longer request-pipeline stability runner for the depth candidate found by
the compact sweep diagnosis.

New mode:

```bash
scripts/run-naru-live-benchmark.sh request-pipeline-stability
```

The mode runs a fixed VNC-only app-low-traffic shape without using a preset, so
the longer sample and duration controls are not overwritten. It compares only
depth `1` and depth `3`:

- constrained-cellular network profile
- request-response transport
- app-low-traffic stream profiles
- phone-portrait viewport request region
- visible-glance first-frame request at scale `0.45`
- `iphone-remote-desktop-10fps-v1` target
- 12 stream-shape samples with a 10 second sustained duration cap

The mode reuses the compact request-pipeline diagnosis report and routes any
below-target stability result to `run-helper-video-live-gate`.

## Live Result

Command:

```bash
NARU_LIVE_VNC_PASSWORD=... scripts/run-naru-live-benchmark.sh request-pipeline-stability
```

Result summary:

- `status`: `completed`
- `baselineDepth`: `1`
- `bestDepth`: `3`
- depth 1 content FPS: `1.78`
- depth 3 content FPS: `1.83`
- content FPS improvement: `32` permille
- depth 1 first-byte-wait p95: `656` ms
- depth 3 first-byte-wait p95: `657` ms
- depth 1 p95 update: `1100` ms
- depth 3 p95 update: `1370` ms
- best product verdict: `fail`
- best primary issue: `first-frame-failed`
- `pipelineHelpfulness`: `notHelpful`
- `targetReadiness`: `below10fpsTarget`
- `promotionReadiness`: `benchmarkOnlyNoPromotion`
- `recommendedNextAction`: `run-helper-video-live-gate`

Interpretation:

- The short depth-3 improvement from the prior diagnosis does not survive a
  longer stability gate.
- First-byte wait stays effectively unchanged, and p95 update latency worsens
  at depth 3.
- Do not promote request pipeline depth above 1 for production or opt-in app
  defaults from this evidence.
- The next smoothness unit should move back to helper-video live capture after
  Screen Recording permission is granted to the stable helper app bundle.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh request-pipeline-stability-self-test`
- `scripts/run-naru-live-benchmark.sh request-pipeline-stability -- --stream-shape-request-pipeline-depth 2`
  rejects the managed override
- `NARU_LIVE_VNC_PASSWORD=... scripts/run-naru-live-benchmark.sh request-pipeline-stability`

## Safety

The stability runner emits only fixed labels and aggregate benchmark metrics.
It does not emit host identity, password, ports, helper paths, command lines,
raw stdout/stderr, raw TCP/RFB errors, raw OS errors, coordinates, dimensions,
pixels, byte counts, stimulus command text, draft text, marked text, IME state,
keysyms, helper endpoints, pairing material, or physical device IDs.
