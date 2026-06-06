# Startup Glance Scale Setting

Date: 2026-06-06

Purpose: make the 0.25 and 0.35 visible-glance startup candidates testable on a
physical iPhone without changing the product default or rebuilding between
runs.

## Behavior

- Product default remains `standard-045`.
- Inactive low-traffic RGB565 sessions can cycle startup glance scale through:
  - `standard-045` = 0.45
  - `minimal-035` = 0.35
  - `glance-025` = 0.25
- The setting affects only the first non-incremental viewport-aware startup
  request. Sustained viewport-aware incremental requests keep the existing
  policy.
- The toggle is hidden during active sessions and hidden for standard stream
  profiles where the first-frame visible-glance request is not used.
- Diagnostic collection schema v30 includes only the fixed
  `viewerStartupGlanceScaleMode` label.

The app and diagnostic paths do not emit live pixels, framebuffer dimensions,
coordinates, byte counts, host identity, command text, draft text, marked text,
or IME state for this setting.

## Verification

- AppSettings default encoding remains `{}`.
- AppSettings decode/encode/toggle tests cover the 0.45, 0.35, and 0.25 modes.
- App-model tests verify persisted load, persisted toggle, diagnostic export,
  and the low-traffic first-frame startup request region change for
  `glance-025`.
- Diagnostic export tests verify schema v30 and unsafe
  `viewerStartupGlanceScaleMode` values are clamped to nil.

## Decision

This is a physical-device test enablement step. Do not promote 0.25 as the app
default until a real iPhone visual check proves that the first-useful-paint
patch is recognizable enough for touch navigation.
