# 2026-06-06 Sustained Usability Operating Target

## Goal

The next optimization units should be judged against one practical outcome:
an iPhone session on a private-network Mac is usable for sustained work without
stepped viewport motion, unreliable Compose input, or uncomfortable device
heat, even when the network is constrained enough that traffic pressure matters.

`iphone-sustained-usability-v2` remains the normal sustained benchmark and
diagnostic target. `iphone-poor-network-traffic-v1` is the companion target for
traffic-sensitive candidates and poor-network promotion.

## Promotion Ladder

### 1. Benchmark Green

A streaming implementation can become a physical-device candidate only when a
redacted `sustained-v2-core` or narrower sustained follow-up gate and, for
traffic-sensitive work, the poor-network gate produce one of these fixed
outcomes:

- `streamShapeTransportCadenceDiagnosis.recommendedNextAction =
  runPhysicalDeviceSustainedGate`
- an explicitly documented warning acceptance that names the remaining fixed
  issue/constraint labels and explains why they do not block physical testing

Do not change production streaming defaults from a benchmark that still routes
to `inspectContinuousUpdatesConnection`, `tuneTransportCadence`, or
`compareRequestResponseEncodingProfiles`.
For poor-network traffic work, also block promotion when the gate fails on
`request-region-area-failed`, `payload-read-failed`, first-frame startup fail,
or a sustained first-byte wait warning that has not been explicitly accepted.

### 2. Physical iPhone Green

A production-default candidate needs a 10 minute physical iPhone run that passes
all of these user-facing checks:

- viewport zoom and pan remain continuous during repeated pinch, drag, and
  zoomed trackpad cursor-follow interactions
- Compose input can commit multilingual text reliably, including marked-text
  routes where the keyboard uses composition
- sustained diagnostics do not report `.serious` or `.critical` thermal state
- the tested poor-network candidate does not regress startup survival,
  request-area proxy, payload-read pressure, or sustained tail latency
- the fixed diagnostic decision surface does not route to viewport, Compose,
  thermal, renderer, or stream-cadence remediation

### 3. Default Change

Only after benchmark green and physical iPhone green may a PR change production
transport, encoding, preflight, pacing, or interaction defaults. That PR should
include the benchmark artifact, the physical-device diagnostic summary, and a
short rollback note naming the setting or code path that restores the previous
behavior.

## Current Status

The current live benchmark status is not green:

- request-response is usable enough to produce samples but remains below the
  sustained target
- ContinuousUpdates repeatedly fails before useful samples
- v43 diagnosis routes the next transport unit toward
  `inspectContinuousUpdatesConnection`

That means the next large implementation work should not flip defaults yet.
It should pick one of these larger tracks:

- **Transport track**: fix or conclusively reject the current
  ContinuousUpdates connection/receive path, then rerun the v43 gate.
- **Cadence track**: if request-response remains the usable transport, tune its
  request cadence and backpressure against the v43 gate.
- **Traffic track**: benchmark the app low-traffic profile with
  `sustained-v2-constrained-cellular-app-low-traffic`, then decide whether the
  next unit should reduce first-useful-paint area, payload pressure, or
  sustained update wait.
- **Interaction track**: make zoom, pan, and zoomed trackpad cursor-follow feel
  continuous on iPhone, then close with physical iPhone diagnostics.
- **Input track**: harden Compose marked-text/commit routing under the same
  physical iPhone diagnostic gate.

## Reporting Rules

Artifacts may include only fixed target/verdict/action labels, aggregate gate
counts, aggregate safe label counts, and redacted pass/fail judgments. Do not
store host identity, credentials, port values, raw TCP/RFB errors, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw payloads, raw
FPS, raw timings, command text, command output, draft text, marked text, or IME
state.
