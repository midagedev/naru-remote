# 2026-06-05 Sustained Usability Target v2 Summary

## Trigger

After schema v34 showed that one hidden preflight frame can absorb a cold
startup tail, the remaining practical failure is sustained usability: content
FPS, post-warm-up update latency, client-processing tails, local gesture
smoothness, Compose route confidence, and physical iPhone thermal comfort. This
increment makes that larger target explicit before changing app defaults.

## Target

`iphone-sustained-usability-v2` is the default `VNCLiveBenchmark` practical
target for new streaming work. `iphone-practical-baseline-v1` remains available
for legacy artifact comparisons.

Pass bands:

- Controlled-stimulus content FPS: at least 8 fps.
- Average update latency: at most 180 ms.
- P95 update latency after warm-up: at most 350 ms.
- Client-processing p95: at most 24 ms.
- Renderer full-upload pressure: 0 permille.
- Adaptive client-pressure pacing: at most 100 permille.
- Minimum content samples for a confident read: 8.
- Physical iPhone hand-feel gate: a 10 minute session with immediate local
  zoom/pan, deterministic Compose route diagnostics, and no `.serious` or
  `.critical` thermal state.

Fail bands:

- Content FPS below 4 fps.
- Average update latency above 250 ms.
- P95 update latency above 500 ms.
- Client-processing p95 above 50 ms.
- Renderer full-upload pressure above 50 permille.
- Adaptive client-pressure pacing above 500 permille.
- Any very-slow update sample remains fail-class.

## Implementation

- Bumped `VNCLiveBenchmark` schema to v35.
- Added `--stream-shape-practical-target
  iphone-practical-baseline-v1|iphone-sustained-usability-v2`.
- Made the CLI default target `iphone-sustained-usability-v2`.
- Kept v1 as the default for direct `BenchmarkStreamShapeSummary`
  construction and legacy JSON fallback.
- Added fixed issue codes for average update latency:
  `average-update-warning` and `average-update-failed`.

## Command Shape

```bash
swift build --product VNCLiveStimulusWindow

swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 4 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --stream-shape-stimulus external-command \
  --stream-shape-stimulus-warmup-seconds 0.25 \
  --stream-shape-preflight-frames 1 \
  --stream-shape-practical-target iphone-sustained-usability-v2 \
  --first-frame-profiles none \
  --stream-shape-profiles zrle-isolation \
  --stream-shape-transport request-response \
  --stream-shape-profile-iterations 5 \
  --stream-shape-profile-order rotate \
  --continuous-update-samples 1 \
  --timeout 6 \
  --idle-timeout 1 \
  --ask-password \
  --json
```

Target environment and stimulus command values were configured outside the
artifact. The report emitted only schema v35 safe aggregate fields.

## Live Benchmark

Safe aggregate stream-shape results with one hidden preflight frame and the v2
practical target:

| profile | runs usable/total | avg update | max p95 update | avg content FPS | max client p95 | max ZRLE tile p95 | full upload avg | slow/very slow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | 5/5 | 335 ms | 2623 ms | 1.50 | 2319 ms | 2247 ms | 0 permille | 16/1 |
| `zrle-compression-0` | 5/5 | 214 ms | 484 ms | 1.85 | 185 ms | 178 ms | 0 permille | 14/0 |
| `zrle-compression-0-cursor` | 5/5 | 254 ms | 524 ms | 1.80 | 16 ms | 16 ms | 0 permille | 19/0 |
| `zrle-compression-0-clipboard` | 5/5 | 250 ms | 507 ms | 1.85 | 14 ms | 13 ms | 0 permille | 20/0 |
| `zrle-compression-0-cursor-clipboard` | 5/5 | 210 ms | 379 ms | 1.90 | 17 ms | 16 ms | 0 permille | 15/0 |

Order-neutral recommendation:

- selected profile: `zrle-compression-0-cursor-clipboard`
- reason: lowest average update latency across order-neutral request/response
  runs
- runs: 5 usable / 5 total
- aggregate: average update 210 ms, max p95 update 379 ms, average content FPS
  1.90, full-upload pressure 0 permille

## Interpretation

- The selected profile is still far below the v2 content-FPS floor: 1.90 fps
  versus a 4 fps fail threshold and 8 fps pass threshold.
- Average update latency is warning-class for the selected profile: 210 ms is
  above the 180 ms pass band but below the 250 ms fail band.
- P95 update latency is warning-class for the selected profile: 379 ms is above
  the 350 ms pass band but below the 500 ms fail band.
- Renderer upload pressure stays solved at 0 permille.
- Local decode/apply is not the selected profile's p95 bottleneck, but the
  `local-low-latency` cold-tail still appears in one rotated run. App-side
  preflight and request/server cadence should be evaluated against v2 before a
  production default change.

## Verification

- `swift build --product VNCLiveBenchmark`
  - Result: passed.
- `swift build --product VNCLiveStimulusWindow`
  - Result: passed.
- `swift run VNCLiveBenchmark --help`
  - Result: passed; usage includes `--stream-shape-practical-target`.
- `swift test --filter BenchmarkStreamShapeSummaryTests`
  - Result: passed, 27 tests, 0 failures.
- `swift test`
  - Result: passed, 820 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.
- Live `VNCLiveBenchmark` v35 stimulated `zrle-isolation` request/response run
  with 5 rotated iterations, 1 hidden preflight frame, and
  `iphone-sustained-usability-v2`
  - Result: command succeeded and produced safe aggregate schema v35 output.

## Privacy Rule

This artifact records only fixed profile labels, fixed transport labels, fixed
stimulus labels, fixed preflight counts, fixed practical target names, fixed
verdicts, fixed issue codes, fixed iteration/order ordinals, aggregate timing
summaries, aggregate FPS, aggregate renderer/upload counts, and safe failure
labels. It does not store host identity, credentials, framebuffer dimensions,
rectangle coordinates, pixels, cursor pixels, byte counts, raw samples, raw
payloads, external command text, command output, hidden preflight frame
contents, hidden preflight timings, or raw error text.
