# 2026-06-05 Preflight Stream-Shape Summary

## Trigger

Schema v33 order-neutral scoring showed that first-profile cold-start tails
could dominate a profile matrix. This increment tests whether a short hidden
incremental preflight after the first frame can absorb the cold tail before
measured stream-shape samples.

## Implementation

- Added `VNCLiveBenchmark` schema v34.
- Added `--stream-shape-preflight-frames N`.
- Preflight frames run after the stream-shape first frame and before measured
  samples.
- Preflight timeouts stop the warm-up quietly; hidden frame contents and
  timings are not emitted.
- Production app stream defaults remain unchanged until physical iPhone
  evidence proves the trade-off is worthwhile.

## Command Shape

```bash
swift build --product VNCLiveStimulusWindow

swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 3 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --stream-shape-stimulus external-command \
  --stream-shape-stimulus-warmup-seconds 0.25 \
  --stream-shape-preflight-frames 1 \
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
artifact. The report emitted only schema v34 safe aggregate fields.

## Live Benchmark

Safe aggregate stream-shape results with one hidden preflight frame:

| profile | runs usable/total | avg update | max p95 update | avg content FPS | max client p95 | max ZRLE tile p95 | full upload avg | slow/very slow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | 5/5 | 200 ms | 506 ms | 1.80 | 172 ms | 162 ms | 0 permille | 8/0 |
| `zrle-compression-0` | 5/5 | 243 ms | 502 ms | 1.73 | 171 ms | 166 ms | 0 permille | 13/0 |
| `zrle-compression-0-cursor` | 5/5 | 204 ms | 419 ms | 1.93 | 15 ms | 10 ms | 0 permille | 12/0 |
| `zrle-compression-0-clipboard` | 5/5 | 203 ms | 380 ms | 1.73 | 8 ms | 7 ms | 0 permille | 11/0 |
| `zrle-compression-0-cursor-clipboard` | 5/5 | 217 ms | 497 ms | 1.66 | 14 ms | 13 ms | 0 permille | 11/0 |

Order-neutral recommendation:

- selected profile: `local-low-latency`
- reason: lowest average update latency across order-neutral request/response
  runs
- runs: 5 usable / 5 total
- aggregate: average update 200 ms, max p95 update 506 ms, average content FPS
  1.80, full-upload pressure 0 permille

## Interpretation

- One hidden preflight frame removed the previous very-slow cold tail from the
  `local-low-latency` aggregate: the v33 run had 447 ms average update,
  2452 ms max p95 update, 2139 ms max client-processing p95, and one very-slow
  update; v34 preflight reported 200 ms average update, 506 ms max p95 update,
  172 ms max client-processing p95, and zero very-slow updates.
- The recommendation now selects `local-low-latency`, so there is still no
  encoding-profile reason to change the production default.
- Preflight does not solve the practical-use target by itself. Content FPS is
  still below 2 fps under controlled stimulus, so the next large unit should
  target server/request cadence and physical iPhone thermal hand feel rather
  than only first-tail smoothing.
- App-side hidden preflight should remain disabled until a physical iPhone run
  confirms that hiding one incremental update improves hand feel without making
  the just-connected screen feel stale.

## Verification

- `swift build --product VNCLiveBenchmark`
  - Result: passed.
- `swift build --product VNCLiveStimulusWindow`
  - Result: passed.
- `swift run VNCLiveBenchmark --help`
  - Result: passed; usage includes `--stream-shape-preflight-frames`.
- `swift test --filter BenchmarkStreamShapeSummaryTests --filter BenchmarkStreamShapeProfileSelectionTests --filter BenchmarkStreamShapeProfileOrderModeTests`
  - Result: passed, 37 tests, 0 failures.
- `swift test`
  - Result: passed, 811 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.
- Live `VNCLiveBenchmark` v34 stimulated `zrle-isolation` request/response run
  with 5 rotated iterations and 1 hidden preflight frame
  - Result: command succeeded and produced safe aggregate schema v34 output.

## Privacy Rule

This artifact records only fixed profile labels, fixed transport labels, fixed
stimulus labels, fixed preflight counts, fixed iteration/order ordinals,
aggregate timing summaries, aggregate FPS, aggregate renderer/upload counts,
practical verdict codes, and safe failure labels. It does not store host
identity, credentials, framebuffer dimensions, rectangle coordinates, pixels,
cursor pixels, byte counts, raw samples, raw payloads, external command text,
command output, hidden preflight frame contents, hidden preflight timings, or
raw error text.
