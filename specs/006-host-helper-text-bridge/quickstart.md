# Quickstart: Host Helper Text Bridge

This feature is implemented in slices. These commands define the expected
verification flow for helper text bridge changes and for the bounded
key-event-text probe foundation.

## Spec Validation

```bash
rg -n "NEEDS CLARIFICATION[:]" specs/006-host-helper-text-bridge
```

Expected: no unresolved clarification markers.

## First Implementation Slice

Run after adding core helper state and fake-helper routing:

```bash
swift test --filter HelperTextBridge
swift test --filter HelperTextBridgeTests/testHelperTextBridgePathUsesStableDiagnosticValue
swift test --filter TextInjectionAdapterTests
swift test --filter NaruRemoteAppModelTests/testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed
swift test --filter NaruRemoteAppModelTests/testModelRejectsMismatchedHelperInsertResultID
swift test --filter NaruRemoteAppModelTests/testModelRejectsUTF8ComposeWhenClipboardSupportIsUnconfirmed
swift test --filter TextKeystrokeTranscoderTests
swift test --filter BenchmarkTextKeystrokeProbeReportTests
swift test --filter NaruRemoteAppModelTests
swift test --filter DiagnosticExportTests
swift build --product VNCLiveBenchmark
swift build --product VNCLiveStimulusWindow
```

Expected:
- UTF-8 Compose with unconfirmed VNC clipboard routes to fake helper when reachable.
- The same payload fails safely and retains the draft when helper is unavailable.
- Compose text key-event fallback remains a bounded foundation/probe: Hangul
  syllables produce X11 Unicode keysyms, not remote-IME jamo decomposition, and
  the route is not enabled as the default Compose send behavior.
- The live benchmark text-keystroke probe emits only fixed payload labels,
  encoding labels, stage labels, and event-count buckets. It omits raw text,
  keysyms, target identity, credentials, bytes, dimensions, pixels, raw errors,
  and exact timings.
- The observed text-keystroke probe separates "RFB KeyEvent enqueued" from
  "focused editor inserted text" by using a controlled local AppKit text target
  that emits only fixed observation labels.
- Diagnostics export helper state and fixed failure codes without raw text.

## Probe-Only Unicode KeyEvent Compatibility

Run only when a live private VNC target is intentionally configured through
`NARU_LIVE_MAC_HOST` and `NARU_LIVE_MAC_PASSWORD` or `--ask-password`:

```bash
scripts/run-naru-live-benchmark.sh text-keystroke-probe
scripts/run-naru-live-benchmark.sh text-keystroke-probe -- --text-keystroke-probe-payload ascii
scripts/run-naru-live-benchmark.sh text-keystroke-probe -- --network-condition constrained-cellular
scripts/run-naru-live-benchmark.sh text-keystroke-observed-probe -- --text-keystroke-probe-payload ascii
scripts/run-naru-live-benchmark.sh text-keystroke-observed-probe -- --text-keystroke-probe-payload unicode-hangul
```

Expected:
- `status: sent` in text output or `"status": "sent"` in JSON means the fixed
  payload's KeyEvent down/up sequence was enqueued after a successful live VNC
  first-frame handshake.
- `status: observed-inserted` requires the controlled local text target to
  report `"observationStatus": "matched"`. A send-only pass with
  `"observationStatus": "no-input"` is evidence against promoting raw VNC
  KeyEvents as a Compose text route on that target.
- The command does not confirm the remote editor inserted text and does not
  enable key-event text as the app's default Compose route.

## Future macOS Helper Slice

Run after adding the macOS helper target:

```bash
swift test --filter NaruHelper
swift test --filter NaruHelperNetwork
swift run NaruHelper --capability
swift run NaruHelper --listen --port 5974 --token '<manual-pairing-token>'
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
```

Expected:
- `swift test --filter NaruHelper` passes helper contract and pasteboard-restore tests.
- `swift test --filter NaruHelperNetwork` proves length-prefixed authenticated
  helper transport, insert routing, and in-process revocation.
- `swift run NaruHelper --capability` emits fixed-catalog JSON. On a Mac without
  Accessibility post-event permission, `availability` should be `permissionMissing`.
- `swift run NaruHelper --listen ...` opens a logged-in-user helper TCP endpoint
  for private-network manual pairing tests; the token must not be committed,
  logged, or exported.

Manual evidence required before declaring completion:
- Physical iPhone sends Korean/CJK/emoji Compose text to a focused app on the paired Mac.
- Helper disabled/revoked state blocks subsequent inserts.
- Redacted diagnostic export contains helper catalog state only.

## Privacy Checklist

Search generated diagnostics, logs, and fixtures for obvious forbidden sample
data. Normative spec text is excluded because it must name the forbidden
categories.

```bash
rg -n --glob '*HelperTextBridge*' \
  "localhost|5900|password|focusedApp|windowTitle" \
  artifacts/helper-text-bridge NaruRemote/Tests 2>/dev/null || true
```

Expected: no secrets, helper endpoint, host identity, focused app title, or raw
clipboard contents in committed fixtures. Test strings inside source tests are
allowed only when they are local constants and not diagnostic output.
