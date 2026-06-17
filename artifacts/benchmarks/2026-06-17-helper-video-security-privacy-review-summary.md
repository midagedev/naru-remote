# Helper Video Security And Privacy Review - 2026-06-17

## Scope

This artifact records the cross-cutting security/privacy review for helper-video
capture, helper transport, diagnostic export, benchmark reports, and physical
gate runner summaries.

This is not a physical iPhone Green claim, live FPS improvement claim,
traffic/thermal promotion result, or product-default change. It closes only the
privacy/review evidence needed before the remaining physical iPhone gate.

## Review Findings

- Helper-video pairing uses authenticated private-profile transport frames.
  Tests cover matching profile/secret proofs, wrong proof rejection, wrong
  profile rejection, schema mismatch, message-type mismatch, revocation, and
  capability/start boundaries.
- Helper-video capture capability and permission-request JSON use fixed catalog
  labels. The tests reject raw display identifiers, dimensions, endpoints,
  tokens, hosts, byte labels, raw errors, timing strings, local paths, and build
  artifact paths.
- Helper-video benchmark reports preserve fixed issue/readiness/action labels
  for permission missing, capture-source unavailable, callback-stage stalls,
  synthetic helper pass/fail, external helper unavailable, and sustained cadence
  degradation. Report tests reject helper endpoints, passwords, tokens, byte
  counts, raw errors, raw ScreenCaptureKit identifiers, and sentinel payloads.
- Diagnostic export remains catalog-only for helper video, stream performance,
  input lane, sustained-session assessment, viewport hints, and share payloads.
  Tests reject caller-provided raw details and sensitive sentinels.
- Physical-device and signing runner self-tests emit fixed setup/status labels
  and redaction notes only. They cover helper-video live gate summary routing,
  physical iPhone gate summary evidence, signing variant labels, provisioning
  inventory labels, signing setup action summaries, team inference, and device
  id resolution.

## Harness Stability Fix

During this review, the first selected Swift privacy test slice exposed a
non-product benchmark harness flake:

- `BenchmarkVisualTransportComparisonReportTests/testSyntheticEncodedTCPProbeExercisesVideoToolboxPayloadSourceAndReportsPass`
  returned a timeout-derived failed helper-video report when run after other
  helper-video report tests in the larger selected suite.
- The same test passed when run alone and when the test class ran alone,
  pointing at a too-tight in-process synthetic encoded TCP timeout under
  VideoToolbox/test-suite load rather than a product helper-video failure.

Fix applied:

- The in-process synthetic helper-video TCP probe now uses the same
  frame-budget-aware timeout shape already used by external helper probes.
  This keeps the benchmark privacy gate from reporting false synthetic H.264
  transport failures under normal selected-suite load.

## Verification

Privacy/report Swift slice:

```bash
swift test --filter 'DiagnosticExportTests|BenchmarkHelperVideoReportTests|BenchmarkVisualTransportComparisonReportTests|HelperVideoTests|HelperVideoFakeTransportTests|NaruHelperVideoCaptureCapabilityProbeTests|NaruHelperVideoEncoderPrototypeTests|NaruHelperVideoStreamFramePipelineTests|NaruHelperVideoTransportRequestHandlerTests|NaruHelperTextBridgeCapabilityProbeTests'
```

Result:

```text
Executed 139 tests, with 0 failures (0 unexpected) in 1.410s.
```

Runner self-tests:

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test
scripts/run-naru-live-benchmark.sh physical-signing-variant-probe-self-test
scripts/run-naru-live-benchmark.sh physical-provisioning-profile-inventory-self-test
scripts/run-naru-live-benchmark.sh physical-signing-setup-summary-self-test
scripts/run-naru-live-benchmark.sh physical-team-inference-self-test
scripts/run-naru-live-benchmark.sh physical-device-id-resolution-self-test
```

Result:

- `helper-video-live-gate-self-test=passed`
- `physical-iphone-helper-video-gate-self-test=passed`
- `physical-signing-variant-probe-self-test=passed`
- `physical-provisioning-profile-inventory-self-test=passed`
- `physical-signing-setup-summary-self-test=passed`
- `physical-team-inference-self-test=passed`
- `physical-device-id-resolution-self-test=passed`

## Remaining Risk

- T030 physical iPhone + Mac manual verification is still open. The privacy
  review proves redaction/report boundaries, but it does not prove physical
  iPhone hand-feel, thermal behavior, PiP behavior, or sustained helper-video
  decode on device.
- `TXXX Run all checks listed in quickstart.md` remains open because the
  quickstart includes physical and live credential gates that should not be
  repeated unless the device/signing/helper environment changes.
- The next useful product evidence remains `physical-iphone-helper-video-gate`
  once the physical iPhone is connected, unlocked, trusted, kept awake, and the
  exact app provisioning/signing path is available.

## Privacy

This artifact contains only test names, fixed status labels, aggregate counts,
and coarse durations. It omits hostnames, IP addresses, endpoints, credentials,
pairing material, helper executable paths, physical device identifiers,
provisioning profile names, profile UUIDs, team identifiers, bundle
identifiers, raw xcodebuild logs, raw OS errors, frame pixels, dimensions,
coordinates, byte counts, composed text, clipboard contents, and exact timing
series.
