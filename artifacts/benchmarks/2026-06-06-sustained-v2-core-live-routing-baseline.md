# 2026-06-06 Sustained v2 Core Live Routing Baseline

## Trigger

After schema v41 added top-level `streamShapeOptimizationDecision`, run the
standard live gate once against a configured local VNC target to choose the next
large optimization unit from data instead of continuing small viewport or
encoding tweaks.

## Environment Preflight

Redacted preflight result:

- `canRunLiveBenchmark`: true
- `hostStatus`: configured
- `credentialStatus`: promptRequested
- `portStatus`: defaulted
- `stimulusCommandStatus`: configured
- `stimulusMode`: external-command
- `issueCodes`: none

No host identity, credential value, port value, stimulus command text, pixels,
coordinates, byte counts, or raw connection errors were recorded in this
artifact.

## Live Gate Shape

- schema: v41
- preset: `sustained-v2-core`
- target: `iphone-sustained-usability-v2`
- profiles: core matrix
- transports: request-response and ContinuousUpdates
- iterations: five rotated iterations
- stimulus: configured external command
- app parity: client-pressure and viewport-interaction pacing enabled by preset

## Report-Level Decision

`streamShapeOptimizationDecision`:

| field | value |
| --- | --- |
| verdict | fail |
| gates pass/warning/fail/disabled/blocked/total | 0 / 0 / 8 / 0 / 8 / 8 |
| primary issue | `probe-failed` |
| primary constraint | `receivePath` |
| recommended next probe | `inspectServerTransportCadence` |

Aggregate triage counts:

| label family | counts |
| --- | --- |
| primary constraint | `contentCadence=8`, `receivePath=28`, `clientDecode=4` |
| recommended next probe | `runSustainedV2ProfileGate=8`, `inspectServerTransportCadence=28`, `compareEncodingProfileGate=4` |

## Profile Gate Summary

Every profile gate failed. Request-response probes connected and produced
usable aggregate samples, but content cadence stayed far below the sustained v2
target. ContinuousUpdates probes failed before producing usable samples.

| profile | transport | gate | runs pass/warning/fail/disabled | primary constraint | recommended next probe |
| --- | --- | --- | --- | --- | --- |
| `local-low-latency` | request-response | fail | 0 / 0 / 5 / 0 | `clientDecode` | `compareEncodingProfileGate` |
| `local-low-latency` | continuous-updates | fail | 0 / 0 / 5 / 0 | `receivePath` | `inspectServerTransportCadence` |
| `zrle-compression-0` | request-response | fail | 0 / 0 / 5 / 0 | `clientDecode` | `compareEncodingProfileGate` |
| `zrle-compression-0` | continuous-updates | fail | 0 / 0 / 5 / 0 | `receivePath` | `inspectServerTransportCadence` |
| `tight-first` | request-response | fail | 0 / 0 / 5 / 0 | `receivePath` | `inspectServerTransportCadence` |
| `tight-first` | continuous-updates | fail | 0 / 0 / 5 / 0 | `receivePath` | `inspectServerTransportCadence` |
| `adaptive-good-full` | request-response | fail | 0 / 0 / 5 / 0 | `clientDecode` | `compareEncodingProfileGate` |
| `adaptive-good-full` | continuous-updates | fail | 0 / 0 / 5 / 0 | `receivePath` | `inspectServerTransportCadence` |

## Request-Response Aggregate Snapshot

These are aggregate benchmark values only. They are useful for comparing
candidate profiles and must not be expanded into per-frame samples.

| profile | avg update ms | max p95 update ms | avg content FPS | avg received/request permille | avg content/request permille | renderer full-upload permille | max client-processing p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | 277 | 2381 | 1.78 | 969 | 893 | 0 | 2127 |
| `zrle-compression-0` | 232 | 375 | 1.92 | 963 | 909 | 0 | 144 |
| `tight-first` | 252 | 382 | 1.84 | 1000 | 920 | 0 | 12 |
| `adaptive-good-full` | 241 | 380 | 1.88 | 981 | 906 | 0 | 155 |

Order-neutral recommendation still selected `zrle-compression-0` for
request-response by average update latency, but the report-level gate failed
before any default should change.

## ContinuousUpdates Failure Signal

The standalone ContinuousUpdates probe failed with
`continuous-probe-receive-connection-failed`. The continuous profile probes
failed with the safe fixed label
`stream-continuous-updates-connection-failed`.

Schema v41 keeps that detail in individual probe summaries, while profile gates
and the top-level decision collapse it to `probe-failed`. The next benchmark PR
should promote safe failure-label counts into `streamShapeProfileGates` and
`streamShapeOptimizationDecision` so future report-level routing can distinguish
connect, first-frame, enable, receive, timeout, and decode failure classes
without reading the raw JSON.

## Interpretation

- Renderer full-upload pressure was 0 permille across usable request-response
  aggregates, so GPU upload is not the first blocker for this live run.
- Request-response is usable enough to compare profiles, but content FPS is
  around 1.8-1.9 FPS under the controlled stimulus, well below the 8 FPS target.
- ContinuousUpdates fails at the receive/connection phase and should not be
  promoted as a production default until the server cadence/failure mode is
  understood.
- The next large unit is `inspectServerTransportCadence`, starting with
  gate-level failure-label aggregation and then a targeted transport/cadence
  diagnostic run.

## Verification

- `nc -G 3 -vz <configured-redacted-target> 5900`: succeeded.
- `swift build --product VNCLiveStimulusWindow`: passed.
- `VNCLiveBenchmark --environment-preflight --stream-shape-gate-preset sustained-v2-core --ask-password --json`: passed with no preflight issue codes.
- `VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-core --ask-password --json`: completed and produced schema v41 JSON in `/tmp`; raw JSON was not committed.
