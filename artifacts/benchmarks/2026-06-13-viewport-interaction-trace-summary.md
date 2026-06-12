# Viewport Interaction Trace Summary - 2026-06-13

## Scope

Add a fixed live benchmark entry point for the product-quality requirement
called `viewport-interaction live benchmark trace`.

The new runner mode compares the same VNC target/profile under two viewport
interaction policies:

- `viewport-interaction-off-baseline`
- `viewport-interaction-app-pacing`

Both candidates use the `iphone-remote-desktop-10fps-v1` target, the
`local-low-latency-rgb565` profile, request/response transport, the
phone-portrait viewport request region, and visible-glance startup.

## Result

The trace gives future zoom/pan work a stable live comparison before changing
gesture or frame pacing code. It records whether app viewport interaction
pacing changes content FPS, first-byte wait, update p95, and viewport pacing
sample counters under the same live Mac Screen Sharing condition.

Latest live run on this machine:

- Off baseline: about `5.25` content FPS, product verdict `fail`, primary
  issue `first-byte-wait-failed`, first-byte wait p95 about `512ms`.
- App viewport pacing: about `4.0` content FPS, product verdict `fail`,
  primary issue `first-byte-wait-failed`, first-byte wait p95 about `497ms`.
- App viewport pacing recorded viewport pacing samples, but no paused request
  samples in this run.

This supports the current diagnosis: the immediate VNC visual blocker is still
receive-path/server cadence rather than a client decode or renderer upload
blocker. The trace should be rerun after viewport gesture tuning and after any
server cadence or helper-video primary-path change.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help | rg "viewport-interaction-trace"
scripts/run-naru-live-benchmark.sh viewport-interaction-trace-self-test
scripts/run-naru-live-benchmark.sh viewport-interaction-trace
jq -e '.schemaVersion == 1 and .mode == "viewport-interaction-trace" and .status == "completed" and (.candidates | length == 2) and (.candidates[0].viewportInteractionMode == "off") and (.candidates[1].viewportInteractionMode == "app") and all(.candidates[]; .status == "passed")' /tmp/naru-viewport-interaction-trace-current.json
git diff --check
swift test --filter 'BenchmarkStreamShapePacingPolicyTests|BenchmarkStreamShapeSummaryTests|ViewportInputHotPathDriverTests'
```

All listed checks passed. The Swift test slice executed 97 selected tests.

## Safety

The runner emits fixed target/profile/mode labels, aggregate verdicts, aggregate
FPS and latency summaries, viewport pacing counters, safe progress labels, and
next-action labels. It does not record hostnames, IP addresses, credentials,
device identifiers, helper paths, raw connection logs, framebuffer pixels,
screenshots, byte counts, frame dimensions, pointer coordinates, Compose text,
marked text, keysyms, or clipboard contents.
