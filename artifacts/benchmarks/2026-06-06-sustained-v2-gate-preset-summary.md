# 2026-06-06 Sustained v2 Gate Preset Summary

## Trigger

The practical-usability baseline and environment preflight make the next work
larger, but the live gate command was still a long list of options that could
drift between PRs. This increment adds one standard preset for the first
controlled-stimulus v2 gate run.

## Implementation

- Added `BenchmarkStreamShapeGatePreset`.
- Added `VNCLiveBenchmark --stream-shape-gate-preset none|sustained-v2-core`.
- Bumped `VNCLiveBenchmark` output to schema v38.
- Added `streamShapeGatePreset` to benchmark reports.
- The `sustained-v2-core` preset fixes:
  - attempts: 1
  - full refresh samples: 0
  - stream-shape samples: 0
  - stream-shape duration: 10 seconds
  - content frame interval: 1/60 second
  - idle frame interval: 0.05 seconds
  - empty backoff: app
  - power mode: normal
  - client pressure: app
  - viewport interaction: app
  - stimulus: external command
  - stimulus warmup: 0.25 seconds
  - stream-shape preflight frames: 0
  - practical target: `iphone-sustained-usability-v2`
  - first-frame profiles: none
  - stream-shape profiles: core matrix
  - stream-shape transport: both
  - profile iterations: 5
  - profile order: rotate
  - continuous update samples: 1
  - timeout: 6 seconds
  - idle timeout: 1 second

## CLI Smoke

Command:

```bash
.build/debug/VNCLiveBenchmark \
  --environment-preflight \
  --stream-shape-gate-preset sustained-v2-core \
  --ask-password \
  --json
```

Safe output from the current empty live environment:

```json
{
  "canRunLiveBenchmark" : false,
  "credentialStatus" : "promptRequested",
  "hostStatus" : "missing",
  "issueCodes" : [
    "missing-host",
    "missing-stimulus-command"
  ],
  "portStatus" : "defaulted",
  "schemaVersion" : 1,
  "stimulusCommandStatus" : "requiredMissing",
  "stimulusMode" : "external-command"
}
```

A second preflight smoke with dummy host, credential, and stimulus environment
values reported `canRunLiveBenchmark: true` without exposing the dummy values.

## Interpretation

- Use `sustained-v2-core` as the first gate for large practical-usability PRs.
- A failed preset gate should be interpreted through `streamShapeProfileGates`,
  hit-rate fields, and practical issue codes before changing defaults.
- A passing preset gate is not a production approval by itself; it only
  graduates a candidate to the 10 minute physical iPhone hand-feel/thermal
  gate.

## Verification

- `swift test --filter BenchmarkStreamShapeGatePresetTests`
  - Result: passed, 2 tests, 0 failures.
- `swift test --filter BenchmarkLiveEnvironmentPreflightTests`
  - Result: passed, 5 tests, 0 failures.
- `swift build --product VNCLiveBenchmark`
  - Result: passed.
- `.build/debug/VNCLiveBenchmark --environment-preflight
  --stream-shape-gate-preset sustained-v2-core --ask-password --json`
  - Result: emitted safe missing-setup JSON and did not prompt.
- `git diff --check`
  - Result: passed.

## Privacy

This artifact records only fixed preset labels, fixed status labels, fixed
issue codes, fixed stimulus mode labels, schema versions, and verification
command names. It does not store host identity, credentials, port value,
stimulus command text, command output, TCP errors, RFB errors, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw payloads,
draft text, marked text, or IME state.
