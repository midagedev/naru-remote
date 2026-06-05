# App Stream Profile Experiment Gate Summary - 2026-06-06

This increment connects the benchmark-driven sustained-stream work to the
actual app session lifecycle. It does not change the default VNC stream
profile.

## Goal

Use larger practical-usability units: candidates should move from repeatable
live benchmark gates into a fixed app-side experiment gate, then into physical
iPhone hand-feel and thermal checks before becoming defaults.

## What Changed

- Added a safe `streamEncodingMode` app setting with fixed values:
  `standard`, `zrle-compression-0`, and `adaptive-good-full`.
- Kept `standard` as the default and omitted it from encoded settings.
- Added an inactive-session control for cycling the fixed experiment profile.
- Applied non-standard stream profiles on the next connection by renegotiating
  the configured `RFBEncodingPreference`.
- Kept power saver as the stronger override for thermal behavior.
- Added diagnostic collection schema v27 with the safe fixed
  `viewerStreamEncodingMode` label.

## Verification

- `swift test --filter AppSettingsCodableTests`
- `swift test --filter DiagnosticExportTests`
- `swift test --filter NaruRemoteAppModelTests/testModelPersistsStreamEncodingModeToggle`
- `swift test --filter NaruRemoteAppModelTests/testModelRenegotiatesConfiguredZrleStreamEncodingOnConnect`
- `swift test --filter NaruRemoteAppModelTests/testModelLetsPowerSaverStreamModeOverrideConfiguredEncodingOnConnect`
- Full `swift test`

## Interpretation

Use the app gate only after a benchmark candidate is interesting enough to try
in a real session. A non-standard selection is a reproduction tool, not a
recommendation. The default remains unchanged until sustained v2 benchmark
results and physical iPhone hand-feel/thermal checks agree.

## Safety

The setting and diagnostic export use fixed labels only. They must not store or
emit host identity, credentials, port value, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw timings, raw payloads,
draft text, marked text, or IME state.
