# 2026-06-06 Physical Sustained Candidate Gate Summary

Target: `iphone-sustained-usability-v2`

## Purpose

This increment turns the physical iPhone path from a connect-only smoke into a
larger sustained candidate gate. The gate is meant to evaluate an entire
candidate shape before production defaults change:

- stream power mode
- stream encoding mode
- startup preflight mode
- startup glance scale mode
- viewport pinch/pan and zoomed trackpad movement
- Compose Send route and preparation diagnostics
- delayed active-session diagnostic export

## What Changed

- `PhysicalDeviceConnectE2EUITests` now has
  `testPhysicalDeviceSustainedCandidateGate`.
- The sustained test is opt-in via `NARU_PHYSICAL_E2E_SUSTAINED_SECONDS`; the
  recommended promotion duration remains 600 seconds.
- The test forwards only fixed candidate labels into the app:
  `balanced|power-saver`,
  `standard|local-low-latency-rgb565|zrle-compression-0|zrle-compression-0-rgb565|adaptive-good-full`,
  `disabled|one-hidden-frame`, and
  `standard-045|minimal-035|glance-025`.
- All four candidate labels are required once the sustained gate is enabled, so
  a run cannot accidentally fall back to persisted or default settings.
- The app can apply those labels for a test launch without persisting them to
  the device settings store.
- Active-session test logging now emits through `makeDiagnosticExport()`, so
  the final log can include stream performance, startup preflight, startup
  glance scale, Compose route/preparation, sustained-session triage, and
  `physicalGateVerdict`.

## Gate Interpretation

Use the final `NARU_DIAGNOSTIC_EXPORT` block from the xcodebuild log.

- `sustainedSessionAssessment.physicalGateVerdict = pass`: the diagnostic half
  of the physical gate is green. A default-changing PR still needs the matching
  sustained v2 benchmark artifact and manual hand-feel notes.
- `sustainedSessionAssessment.physicalGateVerdict = blocked`: do not change
  production defaults. Use `primaryConstraint` and `recommendedNextProbe` to
  choose the next large unit.

This PR does not claim the current app passes the physical gate and does not
change production transport, encoding, preflight, pacing, or interaction
defaults.

## Verification

- `swift test` passed locally.
- The new sustained UI test compiled and skipped on iPhone 17 Pro simulator
  when `NARU_PHYSICAL_E2E_SUSTAINED_SECONDS` was unset.
- A no-secret physical-device skip attempt reached Xcode signing, then stopped
  before install because local iOS development provisioning profiles were not
  available for the app and UI-test runner bundle ids. No host, password, or
  sustained diagnostic payload was used for that attempt.

## Safe Reporting

Do not commit the physical run's host, password, port, device id, raw
diagnostic payload, screenshots, command output, draft text, marked text, IME
state, framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts,
raw timings, raw FPS, raw TCP/RFB errors, or raw payloads.
