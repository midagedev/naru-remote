# 2026-06-06 Sustained v2 Core v42 Transport Cadence Baseline

## Trigger

After schema v42 promoted safe `failureLabelCounts` into profile gates and the
top-level optimization decision, rerun the standard live
`sustained-v2-core` gate against the configured local VNC target. The goal is
to choose the next large unit without opening raw probe JSON.

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

- schema: v42
- preset: `sustained-v2-core`
- target: `iphone-sustained-usability-v2`
- transports: request-response and ContinuousUpdates
- profile iterations: five rotated iterations
- stimulus: configured external command
- app parity: preset client-pressure and viewport-interaction pacing

## Report-Level Decision

`streamShapeOptimizationDecision`:

| field | value |
| --- | --- |
| verdict | fail |
| gates pass/warning/fail/disabled/blocked/total | 0 / 0 / 8 / 0 / 8 / 8 |
| primary issue | `probe-failed` |
| primary constraint | `receivePath` |
| recommended next probe | `inspectServerTransportCadence` |
| failure labels | `stream-continuous-updates-connection-failed=20` |

Aggregate triage counts:

| label family | counts |
| --- | --- |
| primary constraint | `contentCadence=9`, `receivePath=26`, `clientDecode=5` |
| recommended next probe | `runSustainedV2ProfileGate=9`, `inspectServerTransportCadence=26`, `compareEncodingProfileGate=5` |

## Transport Split

| transport | gate count | blocked gates | status signal |
| --- | ---: | ---: | --- |
| request-response | 4 | 4 | usable samples, below target |
| ContinuousUpdates | 4 | 4 | failed before usable samples |

Request-response profile gates had no failure labels and kept high aggregate
received-sample permille, but all failed the sustained target. ContinuousUpdates
profile gates all reported `stream-continuous-updates-connection-failed`.

## Request-Response Snapshot

| profile | gate | primary constraint | received/request permille | content/request permille |
| --- | --- | --- | ---: | ---: |
| `local-low-latency` | fail | `clientDecode` | 969 | 949 |
| `zrle-compression-0` | fail | `clientDecode` | 980 | 934 |
| `tight-first` | fail | `clientDecode` | 981 | 849 |
| `adaptive-good-full` | fail | `receivePath` | 971 | 961 |

Order-neutral recommendation selected `tight-first` by aggregate
request-response latency, but the report-level target still failed and should
not change production defaults.

## ContinuousUpdates Snapshot

| profile | gate | failure label |
| --- | --- | --- |
| `local-low-latency` | fail | `stream-continuous-updates-connection-failed=5` |
| `zrle-compression-0` | fail | `stream-continuous-updates-connection-failed=5` |
| `tight-first` | fail | `stream-continuous-updates-connection-failed=5` |
| `adaptive-good-full` | fail | `stream-continuous-updates-connection-failed=5` |

Standalone ContinuousUpdates probe also failed with
`continuous-probe-receive-connection-failed`.

## Interpretation

- v42 is sufficient to show that ContinuousUpdates is repeatedly failing before
  useful stream samples.
- v42 still requires the operator to manually compare request-response and
  ContinuousUpdates gates to choose the next transport/cadence action.
- The next schema should add a report-level transport/cadence diagnosis that
  emits fixed transport statuses and a fixed next-action label. For this
  baseline, the expected action is `inspectContinuousUpdatesConnection`.

## Verification

- `nc -G 3 -vz <configured-redacted-target> 5900`: succeeded.
- `swift build --product VNCLiveStimulusWindow`: passed.
- `swift build --product VNCLiveBenchmark`: passed.
- `VNCLiveBenchmark --environment-preflight --stream-shape-gate-preset sustained-v2-core --ask-password --json`: passed with no preflight issue codes.
- `VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-core --ask-password --json`: completed and produced schema v42 JSON in `/tmp`; raw JSON was not committed.
