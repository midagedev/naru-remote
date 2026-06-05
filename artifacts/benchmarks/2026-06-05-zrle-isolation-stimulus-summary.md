# 2026-06-05 ZRLE Isolation Stimulus Summary

## Trigger

The dynamic stimulus baseline showed that `local-low-latency` can still hit a
2 second-class ZRLE tile/apply spike while pure ZRLE compression 0 remains low
on client-processing p95. This increment adds a named isolation matrix so
cursor and ExtendedClipboard pseudo-encoding requests can be compared under the
same repeatable animated content.

## Implementation

- Added `--stream-shape-profiles zrle-isolation`.
- The named matrix expands to:
  - `local-low-latency`
  - `zrle-compression-0`
  - `zrle-compression-0-cursor`
  - `zrle-compression-0-clipboard`
  - `zrle-compression-0-cursor-clipboard`
- Updated CLI usage/help and profile-selection tests.

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
  --stream-shape-profiles zrle-isolation \
  --stream-shape-transport request-response \
  --continuous-update-samples 1 \
  --timeout 6 \
  --idle-timeout 1 \
  --ask-password \
  --json
```

Target environment and stimulus command values were configured outside the
artifact. The report emitted only schema v32 safe aggregate fields.

## Live Benchmark

The live run used local macOS Screen Sharing and the repo-native animated
stimulus window helper. Safe aggregate stream-shape results:

| profile | status | verdict | issues | samples | content FPS | update p50/p95 | network p95 | client p95 | ZRLE inflate p95 | ZRLE tile p95 | full upload | slow/very slow |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | content-update | fail | `content-fps-failed`, `p95-update-failed`, `client-processing-failed`, `very-slow-update`, `adaptive-pressure-failed` | 8/8 | 1.33 | 165/2667 ms | 466 ms | 2200 ms | 67 ms | 2132 ms | 0 permille | 4/1 |
| `zrle-compression-0` | content-update | fail | `content-fps-failed` | 12/12 | 2.00 | 153/373 ms | 370 ms | 3 ms | 1 ms | 3 ms | 0 permille | 6/0 |
| `zrle-compression-0-cursor` | mixed-updates | fail | `content-fps-failed`, `client-processing-failed` | 13/13 | 2.00 | 189/395 ms | 393 ms | 161 ms | 3 ms | 158 ms | 0 permille | 4/0 |
| `zrle-compression-0-clipboard` | content-update | fail | `content-fps-failed` | 12/12 | 2.00 | 149/368 ms | 368 ms | 2 ms | 0 ms | 1 ms | 0 permille | 5/0 |
| `zrle-compression-0-cursor-clipboard` | content-update | fail | `content-fps-failed` | 12/12 | 2.00 | 158/443 ms | 431 ms | 12 ms | 0 ms | 12 ms | 0 permille | 6/0 |

Automatic recommendation:

- selected profile: `zrle-compression-0-cursor`
- reason: lowest average update latency among request/response profiles
- caveat: the selected profile still failed client-processing, and all profiles
  failed the practical content-FPS target on this macOS Screen Sharing run

## Interpretation

- `local-low-latency` and `zrle-compression-0-cursor-clipboard` request the
  same request/response ZRLE compression-0, server-cursor, and
  ExtendedClipboard preference, but only the first profile in this run hit the
  2 second-class tile/apply tail. Treat that as an order/cold-start confound,
  not evidence that the production default is inherently worse.
- Pure `zrle-compression-0` and `zrle-compression-0-clipboard` stayed below
  5 ms client p95 while preserving 0 permille full-upload pressure. The
  practical ceiling is still content FPS and server/network pacing, not Metal
  upload pressure.
- Do not change the production default from this single ordered run. The next
  larger unit should add order-neutral live benchmarking: repeated iterations,
  profile rotation, or an explicit warm-up profile before candidate scoring.

## Verification

- `swift test --filter BenchmarkStreamShapeProfileSelectionTests`
  - Result: passed, 12 tests, 0 failures.
- `swift run VNCLiveBenchmark --help | rg -n "zrle-isolation|stream-shape-profiles"`
  - Result: usage and option text include `zrle-isolation`.
- Live `VNCLiveBenchmark` v32 stimulated `zrle-isolation` request/response run
  - Result: command succeeded and produced safe aggregate schema v32 output.
- `swift build --product VNCLiveBenchmark`
  - Result: succeeded.
- `swift build --product VNCLiveStimulusWindow`
  - Result: succeeded.
- `swift test`
  - Result: passed, 807 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: succeeded.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: succeeded.

## Privacy Rule

This artifact records only fixed profile labels, fixed transport labels, fixed
stimulus labels, aggregate timing summaries, aggregate FPS, aggregate
renderer/upload counts, practical verdict codes, and safe failure labels. It
does not store host identity, credentials, framebuffer dimensions, rectangle
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads,
external command text, command output, or raw error text.
