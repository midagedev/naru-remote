# Request Pipeline Diagnosis Summary — 2026-06-09

## Scope

Add a compact, privacy-safe diagnosis mode for the existing launchctl-backed
VNC request pipeline depth sweep.

New mode:

```bash
scripts/run-naru-live-benchmark.sh request-pipeline-sweep-diagnosis
```

The existing `request-pipeline-sweep` mode still emits the raw depth 1/2/3
benchmark report array. The new diagnosis mode captures that array locally and
emits one fixed summary object with:

- baseline depth and best depth
- aggregate content FPS, average/p95 update timing, and first-byte-wait p95
- `pipelineHelpfulness`
- `recommendedNextAction`
- per-depth compact candidate rows

## Live Result

Command:

```bash
NARU_LIVE_VNC_PASSWORD=... scripts/run-naru-live-benchmark.sh request-pipeline-sweep-diagnosis
```

Result summary:

- `status`: `completed`
- `baselineDepth`: `1`
- `bestDepth`: `3`
- depth 1 content FPS: `1.68`
- depth 3 content FPS: `2.36`
- content FPS improvement: `403` permille
- depth 1 first-byte-wait p95: `614` ms
- depth 3 first-byte-wait p95: `618` ms
- depth 3 average update: `492` ms
- depth 3 p95 update: `1119` ms
- best product verdict: `fail`
- best primary issue: `first-frame-payload-read-failed`
- `pipelineHelpfulness`: `helpful`
- `targetReadiness`: `below10fpsTarget`
- `promotionReadiness`: `benchmarkOnlyNeedsLongerStability`
- `recommendedNextAction`: `rerun-request-pipeline-sweep-with-longer-samples`

Interpretation:

- A bounded request pipeline can improve short-run content FPS on the current
  Mac Screen Sharing target, but it remains far below the 10fps product target.
- First-byte wait does not materially improve at depth 3 in this run, and p95
  update latency remains above one second.
- Do not promote request pipeline depth above 1 as a production default from
  this evidence. Treat it as a benchmark-only candidate that needs a longer
  stability pass before any app behavior changes.
- Since RFC 6143 keeps normal framebuffer updates client-requested and the
  ContinuousUpdates/Fence path is an extension recorded separately from the
  baseline RFB flow, helper-video remains the smoother visual transport path
  until the VNC gate reaches product-grade FPS.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh request-pipeline-sweep-diagnosis-self-test`
- `NARU_LIVE_VNC_PASSWORD=... scripts/run-naru-live-benchmark.sh request-pipeline-sweep-diagnosis`

## Safety

The new diagnosis emits only fixed labels and aggregate benchmark metrics. It
does not emit host identity, password, ports, helper paths, command lines, raw
stdout/stderr, raw TCP/RFB errors, raw OS errors, coordinates, dimensions,
pixels, byte counts, stimulus command text, draft text, marked text, IME state,
keysyms, helper endpoints, pairing material, or physical device IDs.

## References

- RFC 6143, Remote Framebuffer Protocol:
  https://www.rfc-editor.org/rfc/rfc6143
- IANA Remote Framebuffer registry:
  https://www.iana.org/assignments/rfb/rfb.xhtml
