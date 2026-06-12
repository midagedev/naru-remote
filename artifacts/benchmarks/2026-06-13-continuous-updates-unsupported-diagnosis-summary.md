# ContinuousUpdates Unsupported Diagnosis Summary - 2026-06-13

## Scope

Refine the transport cadence diagnosis for the live 10fps VNC gate when
ContinuousUpdates fails before samples because the server never confirms the
extension.

## Protocol Basis

The community RFB protocol documents ContinuousUpdates as pseudo-encoding
`-313`. A client advertises support by including that pseudo-encoding in
`SetEncodings`. The server confirms support by sending an
`EndOfContinuousUpdates` server message the first time it sees that
pseudo-encoding. Servers that do not support an extension may ignore the
pseudo-encoding, so the client must treat lack of confirmation as lack of
support for that extension.

Reference: <https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst>

## Result

`BenchmarkStreamShapeTransportCadenceDiagnosis` now maps the fixed failure
label `stream-continuous-updates-continuous-updates-not-confirmed` to
`treatContinuousUpdatesAsUnsupportedForCurrentServer` instead of the broader
`inspectContinuousUpdatesConnection`.

Connection failures and other pre-sample transport failures still route to
`inspectContinuousUpdatesConnection`.

## Live Evidence

The current Mac Screen Sharing target still reports:

- request/response: about `6.06` content FPS, product verdict `fail`,
  next action `tuneTransportCadence`
- ContinuousUpdates: failure label
  `stream-continuous-updates-continuous-updates-not-confirmed`, status
  `failed-before-samples`, next action
  `treatContinuousUpdatesAsUnsupportedForCurrentServer`

This keeps the next visual-smoothness work pointed at helper-video primary
validation and request/response/server cadence rather than repeatedly
re-inspecting a server extension that the current target does not confirm.

## Verification

```bash
swift test --filter 'BenchmarkStreamShapeSummaryTests|BenchmarkFailureLabelTests'
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-transport-cadence-drilldown
jq -e '.candidates[] | select(.transportMode == "continuous-updates") | .report.streamShapeTransportCadenceDiagnosis.recommendedNextAction == "treatContinuousUpdatesAsUnsupportedForCurrentServer"' /tmp/naru-transport-cadence-current.json
git diff --check
```

All checks passed.

## Safety

This artifact records only fixed labels and aggregate benchmark summaries. It
does not include hostnames, IP addresses, credentials, device identifiers,
helper paths, raw connection logs, framebuffer pixels, screenshots, byte
counts, frame dimensions, pointer coordinates, Compose text, keysyms, or
clipboard contents.
