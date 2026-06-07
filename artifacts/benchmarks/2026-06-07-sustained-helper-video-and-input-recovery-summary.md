# Sustained Helper-Video And Input Recovery Summary - 2026-06-07

## Goal

Reproduce the remaining "works in smoke, fails in real use" helper-video and
input symptoms with larger units, then make the benchmark gate reflect the
product goal: non-blocking UI/input plus a sustained visual path that can
eventually replace VNC for smoothness.

## Reproduced

- The two-frame external synthetic helper-video smoke probe passed.
- The sustained external synthetic helper-video probe failed before this change
  with failed startup and stalled sustained health.
- A direct six-frame VideoToolbox synthetic-source regression reproduced the
  underlying issue before transport: low-latency rate-control synthetic batch
  encoding produced dropped/missing output.
- A stale launchctl helper executable could keep the wrapper failing even after
  the SwiftPM helper artifact was fixed.
- Direct key-event timeout handling could cancel the active key emitter, which
  matches the user-visible "one key, then no more keyboard response" symptom.

## Changes

- Added `external-helper-sustained-synthetic-encoded-tcp` and wired
  `helper-sustained-synthetic-probe`, readiness sweep, and short live
  comparison to use a sustained synthetic helper-video gate.
- Split VideoToolbox policy:
  - `completeFrameBatch` for deterministic synthetic helper-video probes.
  - `lowLatencyRealtime` for ScreenCaptureKit capture.
- Treated VideoToolbox frame-dropped callbacks as non-fatal and scaled
  ScreenCaptureKit helper timeouts by requested frame count.
- Corrected external helper `maxServerFrames` to include the start response,
  parameter set, and requested media frames.
- Added fixed safe issue labels for external helper unavailable, timed-out, and
  transport-failed cases.
- Kept Direct key-event emission recoverable after a write timeout by recording
  diagnostics without tearing down the active emitter.
- Refreshed the launchctl helper executable setting to the current SwiftPM
  helper artifact for subsequent benchmark runs.

## Evidence

- `swift test --filter DirectKeystrokeModeTests/testTimedOutKeyEmissionDoesNotPermanentlyDisableLaterKeys`
  passed.
- `swift test --filter NaruHelperVideoEncoderPrototypeTests/testToolboxSyntheticAccessUnitSourceEmitsSustainedFrameBatch`
  passed.
- `swift test --filter NaruHelperVideoListenRuntimeTests/testExternalHelperProcessSendsSustainedSyntheticEncodedBatch`
  passed.
- `swift test --filter BenchmarkHelperVideoReportTests` passed.
- `scripts/run-naru-live-benchmark.sh helper-sustained-synthetic-probe`
  emitted helper-video `streamState=healthy`, `startupBand=fast`,
  `sustainedUpdateBand=smooth`, `codecProfile=high`, and empty issue codes
  after launchctl was updated to the current helper artifact.
- `scripts/run-naru-live-benchmark.sh helper-readiness-sweep` emitted
  `synthetic=pass` and `sustained=pass`; ScreenCaptureKit remained blocked by
  fixed permission/setup labels.
- Running the wrapper against the stale helper artifact emitted fixed
  `helper-video-transport-failed` instead of only a generic helper-video
  failure.

## Current Read

The sustained synthetic helper-video transport is now a meaningful local gate.
It does not complete true ScreenCaptureKit or physical iPhone sustained
verification; T030/T031 still require real capture, decode, thermal, and input
evidence on device.

## Privacy Boundary

This artifact intentionally omits helper paths, launchctl values, host identity,
endpoints, credentials, physical device identifiers, raw logs, pixels, byte
counts, exact timings, Compose text, marked text, and IME state.
