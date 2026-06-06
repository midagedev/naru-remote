# App View-Aware Request Region Summary — 2026-06-06

## Scope

- App-side opt-in traffic experiment for poor-network VNC sessions.
- The production standard stream profile remains full-frame.
- Viewport-aware request regions are enabled only for the fixed
  `zrle-compression-0-rgb565` low-traffic stream profile.

## Behavior

- First framebuffer request: full frame.
- Incremental requests in standard profile: full frame.
- Incremental requests in RGB565 low-traffic profile: visible viewport region
  from `ViewportRequestRegionPolicy` when the current zoom/pan transform has a
  meaningful area saving.
- Heartbeat/fallback behavior: inherited from the shared viewport request-region
  policy.
- Power saver override: disables viewport region narrowing together with the
  RGB565 low-traffic profile override.

## Verification

- `NaruRemoteAppModelTests/testModelKeepsFullIncrementalStreamRequestsInStandardProfile`
  verifies that a zoomed transform does not change standard-profile incremental
  requests.
- `NaruRemoteAppModelTests/testModelRequestsVisibleViewportRegionForLowTrafficIncrementalStreamFrames`
  verifies that the opt-in RGB565 low-traffic profile sends a visible-region
  incremental request after the first full frame.
- Existing `ViewportRequestRegionPolicyTests` cover conversion, margin
  expansion, near-full fallback, heartbeat, timeout fallback, and phone-portrait
  crop-fill shape.
- `swift test` passed: 954 tests executed, 10 skipped, 0 failures.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  passed: 4 synthetic frame pipeline benchmark tests, 0 failures.

## Traffic Interpretation

- This PR reduces requested framebuffer area only when the user explicitly
  selects the low-traffic stream profile and the local viewport is meaningfully
  zoomed/cropped.
- It does not claim a default promotion. Physical iPhone poor-network runs still
  need to compare sustained request-area proxy, tail latency, device heat, and
  input/compose correctness before this behavior can graduate beyond the
  opt-in profile.

## Privacy

- No host identity, credentials, ports, framebuffer dimensions, coordinates,
  byte counts, pixels, cursor pixels, payloads, command text, draft text, marked
  text, IME state, raw errors, or per-sample timings are recorded in this
  artifact.
