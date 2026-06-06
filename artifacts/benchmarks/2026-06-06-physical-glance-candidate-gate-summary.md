# 2026-06-06 Physical Glance Candidate Gate Summary

Target: `iphone-sustained-usability-v2` plus the poor-network startup visual
candidate from the app low-traffic track.

## Purpose

The app can now expose 0.45/0.35/0.25 startup glance scale candidates, but the
physical sustained UI test still accepted only the older stream candidate
catalog. That left the real iPhone gate unable to run the strongest current
poor-network candidate without manual tapping or a rebuild.

## What Changed

- The test-only app settings override accepts
  `NARU_TEST_STARTUP_GLANCE_SCALE_MODE`.
- The physical sustained candidate gate forwards the fixed
  `NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE` label.
- The physical gate now accepts the full stream-encoding catalog, including
  `local-low-latency-rgb565` and `zrle-compression-0-rgb565`.
- The sustained candidate attachment includes the startup glance scale label
  alongside power, encoding, preflight, and compose payload class.
- A simulator UI regression test verifies the startup glance scale control is
  hidden for `standard`, visible for `local-low-latency-rgb565`, and cycles from
  `glance-025` back to `standard-045`.

## Candidate Command Shape

Use launch environment, not committed settings, for a 10 minute real iPhone
gate:

```bash
export NARU_PHYSICAL_E2E_SUSTAINED_SECONDS=600
export NARU_PHYSICAL_E2E_STREAM_POWER_MODE=balanced
export NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE=local-low-latency-rgb565
export NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE=one-hidden-frame
export NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE=glance-025
```

The current physical device is offline in Xcode, so this increment only makes
the gate runnable and simulator-testable. It does not claim a physical iPhone
pass and does not change production defaults.

## Safe Reporting

Artifacts may include only fixed candidate labels, pass/fail/skipped outcomes,
and the safe diagnostic export's fixed labels. Do not store host identity,
credentials, port values, device identifiers, screenshots, raw diagnostic JSON,
raw xcodebuild logs, framebuffer dimensions, coordinates, pixels, cursor
pixels, byte counts, raw timings, raw FPS, TCP/RFB error strings, command text,
command output, draft text, marked text, or IME state.
