# 2026-06-05 Order-Neutral Stream-Shape Summary

## Trigger

The stimulated ZRLE isolation matrix showed that `local-low-latency` and
`zrle-compression-0-cursor-clipboard` request the same request/response ZRLE
compression-0, server-cursor, and ExtendedClipboard preference, but only the
first profile in the ordered run hit a 2 second-class tile/apply tail. This
increment adds repeated, rotated stream-shape probes so candidate scoring is
less sensitive to first-profile cold-start behavior.

## Implementation

- Added `VNCLiveBenchmark` schema v33.
- Added `--stream-shape-profile-iterations N`.
- Added `--stream-shape-profile-order fixed|rotate`.
- Added per-probe `iterationOrdinal` and `orderOrdinal`.
- In rotate mode, profile order and transport order both rotate by iteration so
  `both` transport runs do not always start with the same transport mode.
- Added `streamShapeProfileAggregates` and
  `streamShapeOrderNeutralRecommendation`.
- Kept the legacy `streamShapeRecommendation` for single-probe compatibility.
- Kept the legacy top-level `streamShapeProbe` as the first scheduled
  stream-shape probe result, so compatibility output no longer performs an
  extra unscheduled measurement ahead of the rotated matrix.

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
artifact. The report emitted only schema v33 safe aggregate fields.

## Live Benchmark

The live run used local macOS Screen Sharing and the repo-native animated
stimulus window helper. The 5 profile matrix was repeated 5 times with rotation,
so each profile led one iteration.

Safe aggregate stream-shape results:

| profile | runs usable/total | avg update | max p95 update | avg content FPS | max client p95 | max ZRLE tile p95 | full upload avg | slow/very slow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | 5/5 | 447 ms | 2452 ms | 1.73 | 2139 ms | 2066 ms | 0 permille | 11/1 |
| `zrle-compression-0` | 5/5 | 221 ms | 395 ms | 1.80 | 172 ms | 159 ms | 0 permille | 14/0 |
| `zrle-compression-0-cursor` | 5/5 | 234 ms | 570 ms | 1.93 | 173 ms | 168 ms | 0 permille | 14/0 |
| `zrle-compression-0-clipboard` | 4/5 | 226 ms | 443 ms | 2.08 | 15 ms | 14 ms | 0 permille | 11/0 |
| `zrle-compression-0-cursor-clipboard` | 5/5 | 205 ms | 375 ms | 1.99 | 15 ms | 11 ms | 0 permille | 12/0 |

Order-neutral recommendation:

- selected profile: `zrle-compression-0-cursor-clipboard`
- reason: lowest average update latency across order-neutral request/response
  runs
- runs: 5 usable / 5 total
- aggregate: average update 205 ms, max p95 update 375 ms, average content FPS
  1.99, full-upload pressure 0 permille

## Interpretation

- The cold-start confound is now visible instead of hidden. The first iteration
  still reproduced a 2 second-class `local-low-latency` ZRLE tile/apply tail,
  but later rotated `local-low-latency` runs stayed in the same range as the
  compression-0 variants.
- Order-neutral scoring prefers `zrle-compression-0-cursor-clipboard`, which
  matches the production `local-low-latency` request/response preference. That
  means the optimization target is startup/session warm-up behavior and server
  pacing, not a production encoding preference flip.
- Renderer full-upload pressure remained 0 permille in every aggregate. The
  remaining practical failures are content FPS, server/network/update cadence,
  and occasional first-profile client-processing tails.
- The next larger unit should add an explicit warm-up/preflight stream-shape
  probe or app-side session warm-up policy, then compare physical iPhone heat
  and hand feel with order-neutral scoring.

## Practical Target Bands

Use schema v33 rotated profile scoring as the default gate for larger VNC
optimization PRs.

Do-not-regress gate:

- 5 rotated `zrle-isolation` request/response iterations complete without
  leaking unsafe target, dimension, byte, pixel, coordinate, command, or raw
  timing data.
- Selected order-neutral profile stays at 0 permille renderer full-upload
  pressure.
- Selected order-neutral profile stays at or below 250 ms average update,
  500 ms max p95 update, and 30 ms max client-processing p95.
- No change to the production default is accepted from a single fixed-order
  profile matrix.

Practical-use target:

- Controlled-stimulus content FPS reaches 8 fps or better in normal power on
  the local Screen Sharing target, with a 15 fps stretch target.
- Average update latency reaches 180 ms or better, with p95 below 350 ms after
  warm-up.
- Local zoom/pan transforms stay immediate during active gestures; remote
  decode/upload work must not compete with the visible gesture transform.
- Physical iPhone 10 minute session avoids `.serious` or `.critical` thermal
  state while preserving deterministic Compose route diagnostics.

## Verification

- `swift test --filter BenchmarkStreamShapeProfileOrderModeTests --filter BenchmarkStreamShapeSummaryTests --filter BenchmarkStreamShapeProfileSelectionTests`
  - Result: passed, 37 tests, 0 failures.
- `git diff --check`
  - Result: passed.
- `swift run VNCLiveBenchmark --help`
  - Result: passed; usage includes the new profile iteration/order flags.
- `swift build --product VNCLiveBenchmark`
  - Result: passed.
- `swift build --product VNCLiveStimulusWindow`
  - Result: passed.
- `swift test`
  - Result: passed, 811 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.
- Live `VNCLiveBenchmark` v33 stimulated `zrle-isolation` request/response run
  with 5 rotated iterations
  - Result: command succeeded and produced safe aggregate schema v33 output.

## Privacy Rule

This artifact records only fixed profile labels, fixed transport labels, fixed
stimulus labels, fixed iteration/order ordinals, aggregate timing summaries,
aggregate FPS, aggregate renderer/upload counts, practical verdict codes, and
safe failure labels. It does not store host identity, credentials, framebuffer
dimensions, rectangle coordinates, pixels, cursor pixels, byte counts, raw
samples, raw payloads, external command text, command output, or raw error
text.
