# 2026-06-17 Simulator-Only Timeout-Hardened Gate Summary

## Context

The active validation loop is now simulator-only. Physical iPhone/iPad runs are
out of scope until the operator explicitly re-enables physical-device testing.
Raw physical-device run logs from the abandoned handoff were removed because
they can include local signing, profile, path, and device context that is not
needed for product-quality evidence.

An hourly GitHub issue triage automation was created with id
`naru-remote-hourly-github-issue-roadmap-triage`. Its prompt requires
simulator, fake-server, and local benchmark evidence by default, and allows PRs
only when a clear measured product or performance improvement is available.

## Runner Change

- `run_with_wall_timeout` now terminates child processes of the wrapped command
  before killing the command itself on timeout.
- The same helper now also terminates the watchdog child on normal completion,
  preventing the watchdog sleep from holding self-tests open until the full
  timeout expires.
- `simulator-input-viewport-gate` now wraps each step with
  `NARU_SIMULATOR_GATE_STEP_TIMEOUT_SECONDS` using a safe default of `600`
  seconds.
- Each simulator gate step prints progress to stderr and emits
  `.timedOut` safe failure labels plus `timeoutSeconds` in the JSON report when
  a step exceeds the bound.

## Verification

Syntax and self-test:

```sh
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate-self-test
```

Result: passed. The self-test covers iPhone-only, iPad-default, and
iPad-full-storm stubbed gate shapes without requiring a simulator.

iPhone simulator gate:

```sh
NARU_SIMULATOR_GATE_INCLUDE_IPAD=0 \
NARU_SIMULATOR_GATE_STEP_TIMEOUT_SECONDS=180 \
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Result: passed with `deviceCoverageLabels=["iphone-simulator"]`.

Passed steps:

- `swift-focused-unit-slice`
- `iphone-compose-basic-ui-test`
- `iphone-compose-full-interaction-storm-ui-test`
- `iphone-trackpad-viewport-compose-ui-test`
- `iphone-viewport-hotpath-benchmark`

iPhone + iPad simulator gate:

```sh
NARU_SIMULATOR_GATE_INCLUDE_IPAD=1 \
NARU_SIMULATOR_GATE_INCLUDE_IPAD_FULL_STORM=0 \
NARU_SIMULATOR_GATE_STEP_TIMEOUT_SECONDS=300 \
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Result: passed with
`deviceCoverageLabels=["iphone-simulator","ipad-simulator"]`,
`benchmarkIterations=3`, and `benchmarkSamples=1000`.

Passed steps:

- `swift-focused-unit-slice`
- `iphone-compose-basic-ui-test`
- `iphone-compose-full-interaction-storm-ui-test`
- `iphone-trackpad-viewport-compose-ui-test`
- `iphone-viewport-hotpath-benchmark`
- `ipad-compose-basic-ui-test`
- `ipad-trackpad-viewport-compose-ui-test`

## Product-Quality Reading

This evidence is a gate-runner and regression-safety improvement, not a direct
claim that live VNC streaming now meets the product FPS, latency, heat, or
traffic targets. It makes future simulator-only work safer by ensuring a
stalled xcodebuild or simulator bootstrap step reports a bounded, fixed-label
failure instead of requiring manual interruption.

Physical promotion remains intentionally unclaimed.
