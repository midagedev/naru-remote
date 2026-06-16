# RFB CopyRect In-Place Scroll Performance - 2026-06-16

## Scope

Reduce local CPU and memory pressure in the VNC CopyRect fallback path used by
terminal-like scrolling updates. This benchmark applies one synthetic
1920x1080 framebuffer update that scrolls the previous framebuffer up by one
row through a large overlapping CopyRect rectangle.

This benchmark does not include server wait time, network transfer, Metal
upload, SwiftUI/UIKit layout, physical-device thermal behavior, or live FPS.

## Change

`RFBRawFramebuffer.copyRegionTrackingChange` previously snapshotted the entire
CopyRect source region into a temporary `[RFBColor]` array before writing the
destination. That preserved overlap semantics, but a full-height terminal
scroll created another nearly full-frame pixel array on top of the output
framebuffer copy.

The decoder now chooses row and column direction for the overlap case and
copies directly from `pixels` into the destination, preserving memmove-style
semantics without allocating the source snapshot.

## Commands

Baseline was measured with the benchmark seam added but before the in-place
CopyRect change:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
swift test --filter RFBCopyRectBenchmarkTests/testOverlappingScrollCopyRectBenchmark
```

The same benchmark was rerun after the decoder change. Focused CopyRect and
mixed-encoding regression coverage also passed:

```bash
swift test --filter RFBFramebufferDecoderTests
```

## Results

| Metric | Baseline | Current | Change |
| --- | ---: | ---: | ---: |
| Clock time | `0.291 s` | `0.075 s` | about `74%` lower |
| CPU time | `0.291 s` | `0.074 s` | about `75%` lower |
| CPU cycles | `936761.495 kC` | `239633.414 kC` | about `74%` lower |
| Instructions | `5587536.805 kI` | `1303706.988 kI` | about `77%` lower |
| Peak physical memory | `30895.398 kB` | `22569.050 kB` | about `27%` lower |

The baseline log was `/tmp/naru-copyrect-baseline-20260616-090207.log`; the
current log was `/tmp/naru-copyrect-inplace-current-20260616-090405.log`.

## Product Decision

Use the in-place overlap-safe CopyRect scroll path. This is PR-worthy because
terminal and AI CLI sessions frequently scroll text, CopyRect is the VNC
encoding that represents that movement efficiently, and the benchmark shows a
large local CPU/time reduction while preserving the existing overlap-safety
tests.

This does not change the larger product finding that live VNC smoothness can
still be dominated by server cadence, network waits, helper-video readiness,
rendering/input separation, and physical iPhone thermal behavior.

## Rejected Experiments

- A first in-place version used existential `Sequence` values for row and
  column direction. It reduced peak memory by about 27%, but clock/CPU stayed
  flat and retired instructions increased, so it was replaced by explicit
  branch-local loops.
- The recently measured staged partial-upload `Data(bytesNoCopy:)` variant was
  not repeated here; it lowered instructions slightly but had noisy wall/CPU
  behavior and worse peak memory.
- The recently measured direct H.264 sample-buffer range/block-buffer variant
  was not repeated here; it improved memory in one microbenchmark but did not
  improve clock/CPU enough to justify the extra parser complexity.
- Pure viewport input and static helper app-runner benchmarks were not used as
  this slice's optimization target because the measured runtimes were too small
  and noisy after earlier hot-path work.

Do not repeat those rejected experiments unless a later profile identifies the
same operation as the dominant cost again.

## Safety

This artifact records only aggregate benchmark timings, fixed synthetic
dimensions, and fixed test names. It does not include hostnames, endpoints,
credentials, frame pixels, screenshots, raw payload bytes, profile
fingerprints, device identifiers, Compose text, clipboard contents, raw
network errors, pointer coordinates, or exact per-frame timing series.
