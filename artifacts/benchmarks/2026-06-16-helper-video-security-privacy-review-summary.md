# Helper Video Security And Privacy Review - 2026-06-16

## Scope

This review covers the helper-video capture, transport, diagnostics, benchmark
reports, and app decode path for `specs/007-host-helper-video-stream`.

It is a source/test review. It is not a physical-device security review, App
Store privacy review, or network adversary assessment.

## Commands

Focused privacy and helper-video regression tests:

```bash
swift test --filter 'DiagnosticExportTests|BenchmarkHelperVideoReportTests|HelperVideoStreamSessionRunnerTests|NaruHelperVideoStreamNetworkServiceTests|HelperVideoWireCodecTests|HelperVideoH264SampleBufferRendererTests'
```

Result: passed, 79 tests.

Source scan:

```bash
rg -n "print\\(|NSLog|Logger|logger|os_log|debugPrint|stderr|standardError|rawError|localizedDescription|endpoint|host|password|token|fingerprint|payload|byteCount|bytes|framebuffer|pixels|coordinates|keysyms|clipboard|composed" \
  NaruRemote/Sources/NaruRemoteCore/HelperVideo \
  NaruRemote/App/Features/HelperVideo \
  NaruRemote/Tools/VNCLiveBenchmark \
  NaruHelper/Sources/NaruHelper \
  -g '*.swift'
```

Targeted test scan:

```bash
rg -n "helper-video.*(endpoint|password|token|payload|pixels|byte|dimension|coordinate|raw|error|host)|video.*(endpoint|password|token|payload|pixels|byte|dimension|coordinate|raw error|host)" \
  NaruRemote/Tests NaruHelper/Tests -g '*.swift'
```

## Findings

- Helper-video benchmark reports are covered by tests that prove unsafe fields
  and payload sentinels are omitted.
- Diagnostic export tests cover safe catalog clamping for helper-video report
  fields, input report fields, stream performance fields, and sustained session
  assessment fields.
- Helper-video network-service tests cover rejected pairing secret, safe stall
  frames, timeout handling, slow-consumer coalescing, and sustained event
  stream behavior without printing helper endpoints, credentials, tokens, or
  payloads.
- App decode tests cover Annex-B parser rejection, missing payload/parameter
  handling, renderer behavior, and synthetic helper pipeline conversion without
  logging frame payloads.
- `NaruHelper --video-listen` accepts the helper token as an argument but its
  CLI error output uses fixed messages such as missing-token or unsupported
  mode; it does not print the provided token.
- `VNCLiveBenchmark` still stores live host/password in process memory while
  connecting, as expected for a live benchmark, but JSON/safe summaries emit
  redacted target labels and fixed credential status labels only.
- The helper-video renderer can construct an internal display-layer error from
  `AVSampleBufferDisplayLayer.error?.localizedDescription`; the stream session
  runner maps renderer failures to fixed `.decoderRejected` helper-video state
  and diagnostics export the fixed failure code rather than this raw string.

## Decision

Close the helper-video security/privacy review task for the current
implementation slice. The current source and test evidence supports the
privacy contract used by live gates and benchmark artifacts.

Do not treat this as completion for physical-device runtime privacy until T030
runs on a physical iPhone. A future physical run should still verify that
device logs, copied result bundles, and manual screenshots do not contain
frame content, device identifiers, endpoints, credentials, composed text, or
clipboard contents.

## Privacy

This artifact records test names, fixed source paths, and fixed review
findings only. It does not include live hostnames, endpoints, credentials,
helper tokens, profile fingerprints, device identifiers, frame payloads,
pixels, display dimensions, byte counts, raw OS errors, keysyms, composed
text, pointer coordinates, clipboard contents, or raw result bundles.
