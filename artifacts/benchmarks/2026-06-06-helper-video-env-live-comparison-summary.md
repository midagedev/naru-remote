# Helper Video Environment Live Comparison Summary

Date: 2026-06-06

## Scope

This run verifies that the constrained-cellular helper-video comparison path
uses environment-sourced live credentials and still keeps sensitive connection
values out of reports. It compares the live VNC app-low-traffic candidate set
against the current benchmark-only helper-video report shape.

It does not transmit live helper-video screen frames. The helper-video candidate
still reports `disabled` until a live helper listener, access-unit sender, and
app receiver are connected.

## Commands

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark --environment-preflight --json
```

Preflight result: `canRunLiveBenchmark=true`, `credentialStatus=environment`,
and no issue codes.

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --visual-transport vnc,helper-video \
  --json
```

## Result

- Report schema: `67`.
- Network condition: `constrained-cellular`.
- Visual transports requested: `vnc`, `helper-video`.
- VNC gate verdict: `fail`.
- Primary issue: `first-frame-payload-read-failed`.
- Primary constraint: `receivePath`.
- Best current VNC app-low-traffic candidate:
  `zrle-compression-0-rgb565`.
- Best candidate aggregate: about `2.54` content FPS, about `394 ms` average
  update latency, about `568 ms` p95 update latency.
- Request cadence health: high content hit, p95 warning, next probe
  `inspectUpdateWaitTiming`.
- Transport cadence diagnosis: request/response below target, ContinuousUpdates
  not tested for this preset, next action `tuneTransportCadence`.
- Helper-video candidate verdict: `disabled`.
- Helper-video issue code: `helper-video-stream-disabled`.

## Interpretation

The live credential path is usable and privacy-safe, but the current app-low-
traffic VNC candidate is not practical enough under constrained-cellular
conditioning. The benchmark also confirms that helper-video cannot be promoted
or meaningfully compared until the next implementation unit connects the live
helper access-unit stream to the iOS H.264 sample-buffer path.

## Safety Boundary

- Host, password, server name, framebuffer dimensions, pixel payloads, byte
  counts, cursor pixels, raw error descriptions, stimulus command text, and
  stimulus command output were not emitted.
- The password was supplied only through the environment path.
- The helper-video report emitted only fixed catalog labels and aggregate bands;
  no encoded or decoded frame content was recorded.
