# 2026-06-06 Live Environment Preflight Summary

## Trigger

The practical-usability baseline now expects larger PRs to start from redacted
live schema v37 profile gates when a target is available. The current shell did
not provide live target, credential, or stimulus values, so the benchmark needed
a safe way to report setup readiness before attempting a VNC connection.

## Implementation

- Added `BenchmarkLiveEnvironmentPreflightReport` to `VNCLiveBenchmarkKit`.
- Added `VNCLiveBenchmark --environment-preflight`.
- The preflight exits before any VNC socket is opened.
- The preflight exits before any password prompt is read, even when
  `--ask-password` is present.
- JSON and text output report only:
  - schema version
  - host status
  - port status
  - credential status
  - stream-shape stimulus mode
  - stimulus command status
  - `canRunLiveBenchmark`
  - fixed issue codes

## CLI Smoke

Command:

```bash
.build/debug/VNCLiveBenchmark \
  --environment-preflight \
  --stream-shape-stimulus external-command \
  --json
```

Safe output from the current empty live environment:

```json
{
  "canRunLiveBenchmark" : false,
  "credentialStatus" : "missing",
  "hostStatus" : "missing",
  "issueCodes" : [
    "missing-host",
    "missing-credential",
    "missing-stimulus-command"
  ],
  "portStatus" : "defaulted",
  "schemaVersion" : 1,
  "stimulusCommandStatus" : "requiredMissing",
  "stimulusMode" : "external-command"
}
```

Command:

```bash
.build/debug/VNCLiveBenchmark --environment-preflight --ask-password
```

Safe text output confirmed that no prompt was read and the credential source was
reported as `promptRequested`.

## Interpretation

- `missing-host`: configure the live benchmark target before interpreting
  stream-shape behavior.
- `missing-credential`: provide a password source through the environment or
  use `--ask-password` for the real run.
- `missing-stimulus-command`: controlled-stimulus v37 gates cannot be compared
  yet.
- `invalid-port`: fix the local port configuration before TCP/RFB behavior can
  be diagnosed.

## Verification

- `swift test --filter BenchmarkLiveEnvironmentPreflightTests`
  - Result: passed, 5 tests, 0 failures.
- `swift build --product VNCLiveBenchmark`
  - Result: passed.
- `.build/debug/VNCLiveBenchmark --environment-preflight
  --stream-shape-stimulus external-command --json`
  - Result: emitted safe missing-setup JSON and did not connect.
- `.build/debug/VNCLiveBenchmark --environment-preflight --ask-password`
  - Result: emitted safe text output and did not prompt.

## Privacy

This artifact records only fixed status labels, fixed issue codes, fixed
stimulus mode labels, schema version, and verification command names. It does
not store host identity, credentials, port value, stimulus command text,
command output, TCP errors, RFB errors, framebuffer dimensions, coordinates,
pixels, cursor pixels, byte counts, raw payloads, draft text, marked text, or
IME state.
