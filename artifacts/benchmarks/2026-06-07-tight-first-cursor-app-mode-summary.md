# Tight-First Cursor App Mode Summary - 2026-06-07

## Goal

Expose the current best trackpad-friendly VNC benchmark candidate in the app
without changing the production default. This lets physical iPhone sessions
try the same `tight-first-cursor` profile that won the bounded benchmark while
keeping the default stream path unchanged.

## Change

Added app opt-in stream mode:

- `tight-first-cursor`
- Tight enabled
- Cursor pseudo-encoding enabled
- Tight quality level 8
- compression level 1
- no RGB565 pixel-format override
- no ExtendedClipboard request
- request pipeline depth remains 1

The stream profile toggle now cycles:

```text
standard -> tight-first-cursor -> local-low-latency-rgb565 ->
zrle-compression-0 -> zrle-compression-0-rgb565 ->
adaptive-good-full -> standard
```

## Evidence

Prior live evidence:

- `2026-06-07-tight-first-cursor-candidate-summary.md` selected
  `tight-first-cursor` as the order-neutral recommendation in the bounded
  cursor comparison: 6/6 content samples, 22.47 content FPS, 24 ms average
  update, 32 ms max p95 update, 1 ms max client-processing p95, and 0 permille
  renderer full-upload pressure.
- `2026-06-07-tight-first-cursor-depth-sweep-summary.md` showed request
  pipeline depth should stay at 1: depth 2 did not improve sustained cadence or
  p95 tail enough, and depth 3 failed from client-processing pressure.
- `tight-first-cursor-clipboard` is deliberately not exposed because the ad hoc
  live check failed with 146 ms max client-processing p95.

## Verification

```bash
swift test --filter RFBEncodingTests
swift test --filter AppSettingsCodableTests
swift test --filter NaruRemoteAppModelTests/testModelPersistsStreamEncodingModeToggle
swift test --filter NaruRemoteAppModelTests/testModelBuildsTightCursorStreamConnectorOnConnect
swift test --filter DiagnosticExportTests
swift test --filter BenchmarkStreamShapeProfileSelectionTests
swift run --quiet VNCLiveBenchmark --help | rg "tight-first-cursor|stream-shape"
```

## Interpretation

This is a user-selectable experiment, not a default promotion. It moves the
best benchmark-backed cursor candidate into the app so real iPhone trackpad
sessions can test it, while preserving the existing default and avoiding the
pipeline-depth and clipboard variants that live evidence rejected.

## Privacy

This mode adds only a fixed stream-profile label to app settings and existing
safe diagnostics. It does not log/export host identity, credentials, ports,
request coordinates, dimensions, pixels, byte counts, command text, draft text,
marked text, or IME state.
