# Simulator Gate Step Timeout Summary

Date: 2026-06-16 KST

## Scope

`simulator-input-viewport-gate` is the fast local regression gate for Compose
input responsiveness and viewport interaction. It is supposed to be a repeatable
iteration tool, not an unbounded Xcode wait.

## Trigger

A fresh run of:

```sh
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

started `ComposeInputResponsivenessUITests` on the iPhone 17 Pro simulator and
produced no runner JSON for more than 19 minutes before manual termination.
The simulator was back at the Home screen after termination, which pointed to a
test wrapper/result collection hang rather than an app process still visibly
frozen.

This repeats a known class of failure recorded in
`2026-06-14-compose-input-storm-pacing-summary.md`, where the same gate once
took 3565 seconds before returning a failed result.

## Change

- Added `NARU_SIMULATOR_GATE_STEP_TIMEOUT_SECONDS`, defaulting to 600 seconds.
- Wrapped every `simulator-input-viewport-gate` step in the existing
  `run_with_wall_timeout` helper.
- Added fixed timeout labels by mapping `*.failed` step labels to `*.timedOut`.
- Preserved the local output file path for failed steps so Xcode output can be
  inspected without exporting unsafe app data.
- Added `simulator-input-viewport-gate-step-timeout-self-test` so the timeout
  JSON contract can be checked without launching Xcode.

## Evidence

Fast self-test:

```sh
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate-step-timeout-self-test
```

Result:

```json
{"schemaVersion":1,"mode":"simulator-input-viewport-gate-step-timeout-self-test","status":"passed"}
```

Actual iPhone-only simulator gate with a bounded step timeout:

```sh
env NARU_SIMULATOR_GATE_INCLUDE_IPAD=0 \
  NARU_SIMULATOR_GATE_STEP_TIMEOUT_SECONDS=240 \
  scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Result log:

- `/tmp/naru-simulator-input-viewport-gate-timeout-current-20260616-153303.json`

The gate returned `status=passed` with these steps:

- `swift-focused-unit-slice`: `passed`
- `iphone-compose-storm-ui-tests`: `passed`
- `iphone-viewport-hotpath-benchmark`: `passed`

Additional verification:

- `bash -n scripts/run-naru-live-benchmark.sh`

## Decision

Proceed as a benchmark-runner reliability PR. This is not a product FPS or
input-latency claim. It makes the required local gate bounded and diagnosable,
which prevents future long-running work from silently repeating the same
unbounded Xcode wait.
