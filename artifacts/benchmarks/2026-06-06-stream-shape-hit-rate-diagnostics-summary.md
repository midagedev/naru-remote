# Stream Shape Hit-Rate Diagnostics Summary - 2026-06-06

Target: `iphone-sustained-usability-v2`

Scope:
- `VNCLiveBenchmark` schema v36.
- Safe aggregate stream-shape hit-rate fields for diagnosing low content FPS
  before changing request cadence, transport, encoding profile, or app-side
  startup preflight defaults.

Baseline target:
- Treat `iphone-sustained-usability-v2` as the default streaming gate for the
  next large optimization units.
- Content-bearing update cadence should clear the 8 fps floor before a default
  change is considered usable for sustained iPhone sessions.
- Average update latency should stay in the 180 ms pass / 250 ms fail band, and
  post-warm-up p95 should stay in the 350 ms pass / 500 ms fail band.
- Renderer full-upload pressure should remain 0 permille for the candidate path.
- A production-default change still requires a physical iPhone 10 minute
  hand-feel and thermal pass; simulator and localhost runs only narrow the
  candidate set.

Next large units:
- Frame pipeline: use v36 hit-rate plus existing receive/apply/upload buckets to
  separate unanswered transport waits, empty server responses, decode/apply
  pressure, and renderer upload pressure.
- Viewport interaction: optimize gesture hot-path behavior only against runs
  that include `--stream-shape-viewport-interaction app` plus physical hand-feel
  notes for zoom, pan, and zoomed trackpad auto-pan.
- Compose input: keep marked-text and send-preparation fixes grouped with
  physical Korean/CJK Compose verification instead of treating them as isolated
  text-field tweaks.
- Physical gate: collect redacted app diagnostics and benchmark artifacts from
  the same target profile before changing defaults.

Safe changes:
- Added `attemptedSamples` to distinguish planned/requested samples from the
  number of stream-shape receive attempts actually made during duration-capped
  runs.
- Added summary permille ratios:
  - `receivedSamplePermille`
  - `unansweredSamplePermille`
  - `contentSamplePermille`
  - `emptyResponsePermille`
  - `contentResponsePermille`
- Added profile aggregate/recommendation content hit-rate fields so rotated
  profile comparisons can show whether a selected candidate wins despite low
  content hit-rate. Aggregate permille fields are run-level means so rotated
  benchmark iterations have equal weight when duration-capped attempts vary.
- Updated text output to show received/attempted/requested counts and hit-rate
  permille values beside existing FPS, latency, renderer, and practical target
  fields.

Interpretation:
- Low `receivedSamplePermille` or high `unansweredSamplePermille` points toward
  timeout, server wait, transport, or stimulus/control problems.
- High `receivedSamplePermille` but low `contentResponsePermille` means the
  benchmark is receiving updates, but many are empty; improve controlled
  stimulus or request assumptions before changing app defaults.
- High `contentResponsePermille` with low content FPS points back to update
  latency, network/server wait, decode/apply, renderer pressure, or device
  thermal pressure.

Recommended command shape:

```bash
swift build --product VNCLiveStimulusWindow

swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 10 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --stream-shape-stimulus external-command \
  --stream-shape-stimulus-warmup-seconds 0.25 \
  --stream-shape-preflight-frames 0 \
  --stream-shape-practical-target iphone-sustained-usability-v2 \
  --first-frame-profiles none \
  --stream-shape-profiles zrle-isolation \
  --stream-shape-transport request-response \
  --stream-shape-profile-iterations 5 \
  --stream-shape-profile-order rotate \
  --continuous-update-samples 1 \
  --timeout 6 \
  --idle-timeout 1 \
  --json
```

Run the same shape with `--stream-shape-preflight-frames 1` only for the T390
startup preflight comparison. Treat a preflight comparison as valid only when
the app diagnostic export also shows `startupPreflightOutcome` = `consumed`.

Verification completed in this PR:
- `swift test --filter BenchmarkStreamShapeSummaryTests`
- `swift build --product VNCLiveBenchmark`

Live benchmark status:
- Not run in this increment. The current shell did not have redacted
  `NARU_LIVE_MAC_HOST`, `NARU_LIVE_MAC_PASSWORD`, or
  `NARU_LIVE_STIMULUS_COMMAND` configured. Avoid passing secrets on the command
  line; provide them through the benchmark environment or the hidden password
  prompt when collecting physical-device evidence.

Privacy:
- This artifact records only fixed field names, fixed target names, fixed
  command option names, aggregate counts, permille ratios, and verification
  command names. It contains no host identity, credentials, framebuffer
  dimensions, coordinates, pixels, cursor pixels, byte counts, raw FPS, raw
  timings, raw samples, raw payloads, external command text, command output,
  hidden frame contents, hidden frame timings, raw errors, draft text, marked
  text, or IME state.
