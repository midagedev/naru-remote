# 2026-06-17 Nonphysical Quickstart Gate Summary

## Context

The active development loop is simulator-only until physical devices are
explicitly re-enabled. The existing quickstart still lists physical iPhone,
helper permission, and live VNC commands beside pure package and simulator
checks, which made it easy to repeat unavailable physical-device setup work.

This change adds a single nonphysical quickstart gate for the currently useful
loop. It does not claim physical-device promotion, live FPS improvement,
thermal improvement, or traffic improvement.

## New Command

```sh
scripts/run-naru-live-benchmark.sh nonphysical-quickstart-gate
scripts/run-naru-live-benchmark.sh nonphysical-quickstart-gate-self-test
```

The default gate runs:

- spec clarification scan for `specs/007-host-helper-video-stream`
- helper-video foundation regression slice
- input and viewport unit regression slice
- simulator input/viewport gate self-test
- actual simulator input/viewport gate

It reports `physicalDevicePolicy="excluded"` and uses the fixed
`no-physical-device-required` policy label.

For fast JSON-shape validation without booting simulators:

```sh
NARU_NONPHYSICAL_QUICKSTART_INCLUDE_SIMULATOR_GATE=0 \
scripts/run-naru-live-benchmark.sh nonphysical-quickstart-gate
```

## Verification

Syntax:

```sh
bash -n scripts/run-naru-live-benchmark.sh
```

Result: passed.

Self-test:

```sh
scripts/run-naru-live-benchmark.sh nonphysical-quickstart-gate-self-test
```

Result: passed with checked cases `simulator-gate-skipped` and
`stubbed-swift`.

Fast real gate, simulator UI excluded:

```sh
NARU_NONPHYSICAL_QUICKSTART_INCLUDE_SIMULATOR_GATE=0 \
NARU_NONPHYSICAL_QUICKSTART_STEP_TIMEOUT_SECONDS=300 \
scripts/run-naru-live-benchmark.sh nonphysical-quickstart-gate
```

Result: passed all four non-simulator steps:

- `spec-clarification-scan`
- `helper-video-foundation-tests`
- `input-viewport-unit-tests`
- `simulator-input-viewport-gate-self-test`

Default real gate, simulator UI included:

```sh
NARU_NONPHYSICAL_QUICKSTART_STEP_TIMEOUT_SECONDS=360 \
scripts/run-naru-live-benchmark.sh nonphysical-quickstart-gate
```

Result: passed all five steps:

- `spec-clarification-scan`
- `helper-video-foundation-tests`
- `input-viewport-unit-tests`
- `simulator-input-viewport-gate-self-test`
- `simulator-input-viewport-gate`

## Product-Quality Reading

This gate is now the first command for simulator-only continuation work. It
keeps Compose freeze, input/viewport unit regressions, helper-video foundation
regressions, and iPhone+iPad simulator UI coverage together without depending
on physical iPhone/iPad availability.

It is not a Green product-quality claim because `PRODUCT_QUALITY_TARGETS.md`
still requires physical iPhone evidence for promotion.

## Privacy Rule

The gate may emit fixed step labels, fixed policy labels, pass/fail status,
timeouts, and local temporary output-file paths for failed steps. It must not
emit hostnames, endpoints, credentials, signing identifiers, raw xcodebuild
logs, device identifiers, screenshots, pixels, coordinates, composed text,
clipboard contents, payload bytes, or exact frame timing series.
