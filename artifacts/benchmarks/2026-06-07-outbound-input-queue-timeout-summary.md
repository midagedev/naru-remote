# Outbound Input Queue Timeout Guard Summary

Date: 2026-06-07

## Scope

This increment addresses a local input-pipeline failure mode: a key or pointer
operation that never finishes can hold the shared outbound input queue tail and
make later input feel frozen. It does not change the default VNC encoding
profile, request pacing, or renderer upload policy.

## Change

- Added an app-model timeout backstop around queued key operations and pointer
  command batches.
- Preserved the single shared key/pointer queue for healthy writes, so RFB input
  message order remains deterministic.
- Kept production `RFBNetworkClient`'s socket write timeout as the primary
  network guard; the app-model timeout is a higher-level safety net for stalled
  or non-cooperative clients.

## Verification

- `swift test --filter DirectKeystrokeModeTests` passed.
- `swift test --filter PointerEventTapTests` passed.
- `swift test --filter RemoteInputDockSyncPolicyTests` passed.

New focused regression:

- `DirectKeystrokeModeTests/testTimedOutKeyEmissionReleasesOutboundQueueForLaterPointerInput`
  simulates a stalled key client and verifies that later pointer input can use a
  fresh queue tail after the timeout.

## Live Environment Preflight

`scripts/run-naru-live-benchmark.sh preflight` completed with safe schema-v6
labels:

- `credentialStatus`: `environment`
- `hostStatus`: `configured`
- `portStatus`: `configured`
- `canRunLiveBenchmark`: `false`
- `issueCodes`: `helper-video-permission-missing`
- `setupActionLabels`: `grant-helper-video-app-screen-recording-permission`

Interpretation: live VNC credentials are available through the environment
import path, but helper-video Screen Recording permission still blocks full
helper-video live benchmark passes.

## Privacy

This artifact contains no host identity, credentials, ports, command text,
draft text, marked text, IME state, keysyms, pointer coordinates, dimensions,
pixels, byte counts, raw stdout/stderr, or raw network errors.
