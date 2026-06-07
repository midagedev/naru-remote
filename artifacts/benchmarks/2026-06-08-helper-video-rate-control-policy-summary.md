# Helper Video Rate-Control Policy Summary

Date: 2026-06-08 KST

## Question

After the live VNC path continued to miss the iPhone 10fps product gate and the
true helper-video gate remained blocked by macOS Screen Recording permission,
what can be improved before the next physical iPhone run?

## Decision

Add an explicit helper-side rate-control policy for H.264 helper-video streams.
The policy maps safe stream labels already present in the helper-video contract:

- `qualityBucket`: `readability`, `balanced`, `fidelity`
- `maxFrameRateBucket`: `upTo15`, `upTo30`, `unknown`

to VideoToolbox encoder configuration:

- `kVTCompressionPropertyKey_AverageBitRate`
- `kVTCompressionPropertyKey_DataRateLimits`

The exact values are internal encoder configuration. Diagnostics and benchmark
JSON continue to export only fixed quality/frame-rate/readiness labels and
aggregate health bands.

## Why This Matters

The previous helper-video schema could say `readability` or `balanced`, but the
encoder did not enforce a traffic budget from those labels. That left the
system with a good visual-transport architecture but no concrete poor-network
contract at the compression layer.

For the current product goal, FPS alone is not enough. Sustained iPhone use also
needs bounded traffic, lower heat, and fewer decode/render bursts when the
remote Mac screen changes quickly.

## Current Live State

Latest local live helper-video gate:

- overall gate: `blockedByScreenRecordingPermission`
- Screen Recording final permission: `missing`
- helper readiness/bootstrap: skipped because capture cannot legally proceed

So this work does not claim true live ScreenCaptureKit performance yet. It makes
the next true capture run more meaningful by ensuring the helper encoder is
already constrained by the requested quality/frame-rate bucket.

## Verification

- Unit policy test covers monotonic quality/frame-rate scaling and `unknown`
  frame-rate normalization.
- Encoder test verifies the requested policy is stored on the H.264 pixel-buffer
  encoder.
- Existing helper encoder JSON privacy test still rejects raw `byte` and
  payload fields.
- The live permission-gated helper-video runner still reports the same fixed
  Screen Recording blocker rather than unsafe capture details.

## Next Gate

Grant Screen Recording to the stable helper app bundle, quit/relaunch the
helper, rerun `scripts/run-naru-live-benchmark.sh helper-video-live-gate`, then
run the physical iPhone helper-video gate if the true ScreenCaptureKit path
passes.
