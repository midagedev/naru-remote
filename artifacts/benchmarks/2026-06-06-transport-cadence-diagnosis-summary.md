# 2026-06-06 Transport Cadence Diagnosis Summary

## Target

`iphone-sustained-usability-v2`

## Change

Schema v43 adds top-level `streamShapeTransportCadenceDiagnosis` to
`VNCLiveBenchmark` reports.

The diagnosis separates request-response and ContinuousUpdates before profile
recommendations:

- per-transport status labels: `not-tested`, `disabled`, `pass`,
  `below-target`, `failed-before-samples`
- per-transport blocked/total gate counts
- per-transport primary-constraint counts
- per-transport safe failure-label counts
- recommended transport label
- fixed next-action label

## Why

The v42 live sustained gate exposed repeated ContinuousUpdates failure at the
top level, but still required manual comparison of request-response and
ContinuousUpdates gates. The v43 diagnosis turns that comparison into a fixed
safe routing signal.

## v43 Smoke

A short redacted live smoke used one local-low-latency profile, both transports,
one iteration, external stimulus, and a one-second duration cap. It confirmed
that schema v43 emits the new diagnosis.

Safe result:

| field | value |
| --- | --- |
| request-response status | `below-target` |
| ContinuousUpdates status | `failed-before-samples` |
| recommended transport | `request-response` |
| recommended next action | `inspectContinuousUpdatesConnection` |
| request-response constraints | `clientDecode=1` |
| ContinuousUpdates constraints | `receivePath=1` |
| ContinuousUpdates failure labels | `stream-continuous-updates-connection-failed=1` |

## Interpretation

The next large implementation unit should inspect why ContinuousUpdates fails
at connection/receive time before treating it as a production path. While that
is unresolved, request-response remains the usable transport for profile and
cadence experiments, even though it is still below the sustained v2 target.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`: passed.
- `swift test`: passed.
- `swift build --product VNCLiveBenchmark`: passed.
- `swift run VNCLiveBenchmark --help`: showed schema v43 gate reporting.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`: passed.
- Short redacted v43 live smoke: completed and emitted
  `streamShapeTransportCadenceDiagnosis`; raw JSON stayed in `/tmp`.
- `git diff --check`: passed.
