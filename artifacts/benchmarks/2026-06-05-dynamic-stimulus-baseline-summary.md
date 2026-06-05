# 2026-06-05 Dynamic Stimulus Baseline Summary

## Trigger

The first `core-matrix` baseline made larger PRs easier to compare, but its
content updates still depended on incidental desktop motion. This increment
adds an opt-in dynamic-content stimulus so live stream-shape runs can measure
content FPS against repeatable screen changes.

## Implementation

- Added `VNCLiveBenchmark` schema v32.
- Added `--stream-shape-stimulus off|external-command`.
- Added `--stream-shape-stimulus-warmup-seconds`.
- Added top-level `streamShapeStimulusMode` and
  `streamShapeStimulusWarmupSeconds` report fields.
- Added `VNCLiveStimulusWindow`, a small macOS helper executable that displays
  a deterministic animated window for local Screen Sharing benchmarks.
- `external-command` mode launches `NARU_LIVE_STIMULUS_COMMAND` once per
  stream-shape probe, before the probe's first full frame, so measured
  incremental updates cover the ongoing animation rather than the window's
  first appearance.
- The child starts with a minimal process launch environment plus
  `NARU_LIVE_STIMULUS_DURATION_SECONDS`,
  `NARU_LIVE_STIMULUS_PROFILE_LABEL`, and
  `NARU_LIVE_STIMULUS_TRANSPORT_MODE`; VNC target environment variables and
  the stimulus command variable itself are not forwarded.

## Command Shape

```bash
swift build --product VNCLiveStimulusWindow

swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 6 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --stream-shape-stimulus external-command \
  --stream-shape-stimulus-warmup-seconds 0.25 \
  --first-frame-profiles none \
  --stream-shape-profiles core-matrix \
  --stream-shape-transport request-response \
  --continuous-update-samples 1 \
  --timeout 6 \
  --idle-timeout 1 \
  --ask-password \
  --json
```

Safe top-level settings:

- schema: 32
- stimulus mode: `external-command`
- stimulus warmup: 0.25 seconds
- profiles: `core-matrix`
- transport: request-response
- duration: 6 seconds per probe

## Live Benchmark

The live run used the local macOS Screen Sharing target and the new stimulus
window helper. Safe aggregate stream-shape results:

| profile | status | verdict | issues | samples | content FPS | update p50/p95 | network p95 | client p95 | ZRLE tile p95 | full upload | slow/very slow | actual encoding |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `local-low-latency` | content-update | fail | `content-fps-failed`, `p95-update-failed`, `client-processing-failed`, `very-slow-update`, `adaptive-pressure-failed` | 8/8 | 1.33 | 133/2497 ms | 438 ms | 2213 ms | 2155 ms | 0 permille | 3/1 | ZRLE |
| `zrle-compression-0` | mixed-updates | fail | `content-fps-failed` | 12/12 | 1.83 | 196/374 ms | 371 ms | 7 ms | 6 ms | 0 permille | 6/0 | ZRLE |
| `tight-first` | mixed-updates | fail | `content-fps-failed` | 12/12 | 1.83 | 204/407 ms | 407 ms | 7 ms | n/a | 0 permille | 6/0 | Raw |
| `adaptive-good-full` | mixed-updates | fail | `content-fps-failed`, `client-processing-failed` | 13/13 | 1.83 | 187/404 ms | 363 ms | 153 ms | 151 ms | 0 permille | 3/0 | ZRLE |

Recommendation:

- selected profile: `adaptive-good-full`
- reason: lowest average update latency among successful request/response
  profiles
- caveat: all profiles still fail the practical baseline on content FPS

## Interpretation

- The stimulus path works: every successful request/response profile produced
  content updates under the animated window, with no raw pixels, dimensions,
  command text, or byte counts emitted.
- Starting the stimulus before the first full frame keeps the measured
  stream-shape interval focused on ongoing animation instead of window
  appearance.
- `local-low-latency` reproduced a 2 second-class ZRLE tile/apply spike under
  dynamic content. `zrle-compression-0` kept ZRLE client-processing p95 below
  10 ms in the same run, while `adaptive-good-full` won on average update
  latency but still tripped client-processing. That makes the next large unit a
  profile/extension isolation problem, not a renderer-upload problem.
- Renderer full-upload pressure remained 0 permille across successful probes,
  so the practical failure is not explained by full texture uploads.

## Next Larger Units

- Isolate why `local-low-latency` can hit a very-slow ZRLE tile/apply frame
  under dynamic stimulus while pure ZRLE compression 0 does not in the same
  matrix.
- Compare `local-low-latency`, `zrle-compression-0`,
  `zrle-compression-0-cursor`, and `zrle-compression-0-clipboard` under the
  new stimulus before changing the production default.
- Repeat the stimulated matrix on a physical iPhone once the profile isolation
  run identifies a stable candidate.

## Verification

- `swift build --product VNCLiveBenchmark`
  - Result: succeeded.
- `swift build --product VNCLiveStimulusWindow`
  - Result: succeeded.
- `swift test --filter BenchmarkStreamShapeStimulus --filter BenchmarkFailureLabelTests`
  - Result: passed, 8 tests, 0 failures.
- `swift run VNCLiveBenchmark --help | rg -n "stimulus|NARU_LIVE_STIMULUS|schema|stream-shape-stimulus"`
  - Result: help includes stimulus flags and environment contract.
- Live `VNCLiveBenchmark` v32 stimulated `core-matrix` request-response run
  - Result: command succeeded and produced safe aggregate schema v32 output.
- `swift test`
  - Result: passed, 805 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: succeeded.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: succeeded.

## Privacy Rule

This artifact records only fixed profile labels, fixed transport labels,
fixed stimulus labels, aggregate timing summaries, aggregate FPS, aggregate
renderer/upload counts, practical verdict codes, and safe failure labels. It
does not store host identity, credentials, framebuffer dimensions, rectangle
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads,
external command text, command output, or raw error text.
