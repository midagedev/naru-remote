# Helper Readiness Sweep Summary

Date: 2026-06-07

## Scope

This run verifies a single launchctl-backed readiness command for the next
helper-video live gate. The sweep combines helper capability, live environment
preflight, external synthetic helper-video, and external ScreenCaptureKit
helper-video probes into one privacy-safe JSON object.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, helper stderr, stimulus command text,
or stimulus output are recorded here.

## Command Shape

```bash
scripts/run-naru-live-benchmark.sh helper-readiness-sweep
```

The mode rejects additional arguments so the sub-checks remain fixed and
comparable across runs. If a sub-check exits before producing JSON, the sweep
emits only that sub-check's fixed `step` label plus a fixed `safeFailureCode`.

## Result

- Sweep schema: `1`.
- Helper capability: `permissionMissing`.
- Helper Screen Recording permission: `missing`.
- Permission identity process kind: `appBundle`.
- Permission identity grant hint: `grantAppBundle`.
- Live credential status: `environment`.
- Live host status: `configured`.
- Live port status: `configured`.
- Environment preflight runnable: `false`.
- Preflight issue code: `helper-video-permission-missing`.
- Setup action: `grant-helper-video-app-screen-recording-permission`.
- External synthetic helper-video verdict: `pass`.
- External synthetic stream state: `healthy`.
- External synthetic startup band: `fast`.
- External synthetic sustained band: `smooth`.
- External synthetic decode pressure: `low`.
- External synthetic fallback bucket: `none`.
- External ScreenCaptureKit helper-video verdict: `fail`.
- External ScreenCaptureKit stream state: `failed`.
- External ScreenCaptureKit startup band: `failed`.
- External ScreenCaptureKit sustained band: `stalled`.
- External ScreenCaptureKit decode pressure: `notMeasured`.
- External ScreenCaptureKit fallback bucket: `one`.
- External ScreenCaptureKit issue codes:
  `helper-video-permission-missing`,
  `helper-video-stream-unhealthy`,
  `helper-video-startup-failed`,
  `helper-video-sustained-stalled`,
  `helper-video-fallback-observed`.

## Safe Reduced JSON Shape

This is the reduced shape used for comparing readiness sweeps. It intentionally
omits all live target values, helper paths, endpoints, payloads, dimensions,
byte counts, raw errors, and exact timings.

```json
{
  "schemaVersion": 1,
  "mode": "helper-readiness-sweep",
  "capability": {
    "availability": "permissionMissing",
    "screenRecordingPermission": "missing",
    "safeFailureCode": "helperVideo.permissionMissing",
    "permissionIdentity": {
      "grantHint": "grantAppBundle",
      "processKind": "appBundle"
    }
  },
  "preflight": {
    "schemaVersion": 6,
    "canRunLiveBenchmark": false,
    "credentialStatus": "environment",
    "hostStatus": "configured",
    "portStatus": "configured",
    "helperVideoScreenCapturePermissionStatus": "missing",
    "helperVideoExternalCapability": {
      "status": "permissionMissing",
      "permissionIdentity": {
        "grantHint": "grantAppBundle",
        "processKind": "appBundle"
      }
    },
    "issueCodes": [
      "helper-video-permission-missing"
    ],
    "setupActionLabels": [
      "grant-helper-video-app-screen-recording-permission"
    ]
  },
  "synthetic": {
    "verdict": "pass",
    "streamState": "healthy",
    "startupBand": "fast",
    "sustainedUpdateBand": "smooth",
    "decodePressure": "low",
    "fallbackCountBucket": "none",
    "issueCodes": []
  },
  "screen": {
    "verdict": "fail",
    "streamState": "failed",
    "startupBand": "failed",
    "sustainedUpdateBand": "stalled",
    "decodePressure": "notMeasured",
    "fallbackCountBucket": "one",
    "issueCodes": [
      "helper-video-permission-missing",
      "helper-video-stream-unhealthy",
      "helper-video-startup-failed",
      "helper-video-sustained-stalled",
      "helper-video-fallback-observed"
    ]
  }
}
```

An explicit helper Screen Recording permission request was also attempted
through the fixed-label runner. It returned `requestResult=notGranted` with the
same `permissionMissing` capability state, so the true ScreenCaptureKit
access-unit benchmark remains blocked until macOS grants Screen Recording to
the helper app bundle and the helper process is relaunched.

## Interpretation

The launchctl environment is now sufficient for repeated live checks without
printing credential values, and the external synthetic H.264 helper-video
network/decode path remains green. The next blocker is not RFB credentials or
the helper-video transport; it is macOS Screen Recording approval for the
stable `appBundle` helper identity. After that approval, rerun this sweep and
expect `canRunLiveBenchmark=true` plus a passing external ScreenCaptureKit
probe before attempting the full constrained-cellular helper-video comparison.
