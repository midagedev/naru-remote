# 2026-06-05 ZRLE Bounds And Tail Cooldown Summary

## Trigger

The practical iPhone VNC baseline showed a useful split: median local work was
small, but a single 2 second-class ZRLE client-processing tail made the stream
feel stepped and hot. The same run also showed full-screen dirty-area reports
with only about 1 permille actual changed pixels, causing renderer full-upload
pressure even when the visual change was sparse.

This increment treats that as one larger unit:

- make ZRLE damage rectangles reflect actual changed bounds instead of wire
  rectangle bounds where possible;
- let the renderer upload plan use changed-pixel counts for sparse partial
  uploads;
- enter adaptive client-pressure pacing after one 1000 ms-class local
  decode/apply spike instead of waiting for repeated lagging frames;
- expose the single-spike threshold in redacted `VNCLiveBenchmark` schema v28.

## Baseline Comparison

Reference: `artifacts/benchmarks/2026-06-05-practical-iphone-vnc-baseline-v1-summary.md`.

Safe aggregate baseline from the prior 6 second localhost Screen Sharing run:

- schema: 27
- verdict: `fail`
- issue codes: `content-fps-failed`, `p95-update-failed`,
  `client-processing-failed`, `very-slow-update`, `full-upload-warning`
- transport/profile: request-response / `local-low-latency`
- received/content/empty samples: 8/7/1
- content FPS: 1.17
- update latency p50/p95/max: 145/2512/2512 ms
- client-processing p50/p95/max: 2/2151/2151 ms
- renderer full-upload permille: 143
- actual encoding mix: ZRLE rectangles only

## Changes Measured

`VNCLiveBenchmark` now emits schema v28 and includes
`streamShapeClientPressureVerySlowThresholdMilliseconds`.

Command shape:

```bash
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --stream-shape-profiles local-low-latency \
  --stream-shape-transport request-response \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 6 \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --full-refresh-samples 0 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Safe aggregate result after ZRLE changed-bounds damage:

- schema: 28
- single very-slow client-pressure threshold: 1000 ms
- verdict: `fail`
- issue codes: `content-fps-failed`, `p95-update-failed`,
  `client-processing-failed`, `very-slow-update`,
  `adaptive-pressure-failed`
- transport/profile: request-response / `local-low-latency`
- received/content/empty samples: 8/7/1
- content FPS: 1.17
- update latency p50/p95/max: 186/2501/2501 ms
- client-processing p50/p95/max: 3/2191/2191 ms
- renderer full-upload permille: 0
- renderer partial-upload permille: 1000
- dirty-area p50/p95/max permille: 1/16/16
- changed-pixels p50/p95/max permille: 1/10/10
- renderer upload region count p50/p95/max: 1/38/38
- adaptive client-pressure pacing samples/permille: 7/875
- actual encoding mix: ZRLE rectangles only

## Interpretation

This closes the renderer upload-pressure axis for the measured local target:
full-upload pressure moved from 143 permille to 0, and the practical assessment
no longer reports `full-upload-warning`.

It does not close the practical iPhone baseline. The run still fails on
content FPS, update p95, client-processing p95, and one very-slow update. The
new `adaptive-pressure-failed` issue is expected for this short run because one
very-slow frame now immediately enters the 120-update recovery floor. That is a
thermal/jank guard, not proof that decode/apply tail is fixed.

The next larger unit should target ZRLE decode/apply tail directly, not GPU
upload. Candidate directions:

- avoid redundant per-pixel framebuffer writes/comparisons inside unchanged
  ZRLE tiles;
- compare `local-low-latency` against Tight/Hextile again after changed-bounds
  upload reporting, because the renderer bottleneck changed;
- consider resolution/color-depth policy only after encoding/decode path
  comparisons show it is needed.

## Verification

- `swift test --filter RFBZrleDecoderTests`
  - Result: passed, 9 tests, 0 failures.
- `swift test --filter RFBFramebufferDecoderTests`
  - Result: passed, 20 tests, 0 failures.
- `swift test --filter MetalFramebufferRendererTests`
  - Result: passed, 20 tests, 0 failures.
- `swift test --filter FramebufferUploadPlanTests`
  - Result: passed, 7 tests, 0 failures.
- `swift test --filter BenchmarkStreamShapePacingPolicyTests`
  - Result: passed, 20 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests/testSessionStreamPressurePacingState`
  - Result: passed, 12 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests/testModelAppliesAdaptivePressurePacingInFrameLoop`
  - Result: passed, 1 test, 0 failures.
- `swift test --filter FramebufferUploadGateTests`
  - Result: passed, 5 tests, 0 failures.
- `swift test`
  - Result: passed, 795 tests, 10 skipped, 0 failures.
- Live `VNCLiveBenchmark` 6 second stream-shape run
  - Result: command succeeded, practical baseline verdict `fail`, renderer
    full-upload permille `0`.
- `xcodegen generate --spec project.yml`
  - Result: succeeded.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: succeeded.

## Remaining Risk

- This was measured against localhost macOS Screen Sharing. A physical iPhone
  thermal/hand-feel pass is still required.
- ZRLE changed-bounds reduces renderer work but does not reduce the cost of
  inflating and parsing a full-screen ZRLE update.
- Solid ZRLE tiles still report tile-sized conservative damage when any pixel
  in that tile changes; this is intentionally safe and bounded.
