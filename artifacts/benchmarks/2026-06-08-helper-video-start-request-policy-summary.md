# Helper Video Start Request Policy Summary

Date: 2026-06-08 KST

## Question

After helper-video quality buckets started enforcing VideoToolbox rate control,
does the app actually choose lower helper-video budgets when the phone is likely
to be hot or power constrained?

## Decision

Add an app-side helper-video start request policy before the helper-video
network runner starts capture/encode work.

The app now sends:

- nominal: `readability/upTo30`
- app power saver: `readability/upTo15`
- iOS Low Power Mode: `readability/upTo15`
- thermal `fair`, `serious`, or `critical`: `readability/upTo15`

## Why This Matters

The encoder can enforce a rate cap only after the app picks a request bucket.
Before this change, helper-video bootstrap used the default request body even
when the user had enabled power saver or the system reported low-power/thermal
pressure. That left the poor-network/thermal strategy half-applied.

This keeps helper video aligned with the product goal: sustained iPhone sessions
should prefer readable, bounded traffic first, and only promote higher traffic
after true helper capture plus physical iPhone evidence.

## Verification

- `HelperVideoStartRequestPolicy` unit tests cover nominal and constrained
  states.
- App-model bootstrap tests verify the computed request body reaches the
  helper-video start transport.
- No diagnostic or benchmark schema changes were needed; existing reports keep
  fixed quality/frame-rate/readiness labels.

## Residual Gate

True ScreenCaptureKit helper-video remains blocked until the stable helper app
bundle receives macOS Screen Recording permission. Once that is granted, rerun
`scripts/run-naru-live-benchmark.sh helper-video-live-gate` and then the
physical iPhone helper-video gate.
