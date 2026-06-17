# RFB Raw Uninitialized Buffer Decode Summary

Date: 2026-06-18 KST

Scope: `RFBRawFramebufferDecoder` full-frame Raw first-paint decode path.

## Change

The Raw full-frame decoder now fills the destination `[RFBColor]` with
`Array(unsafeUninitializedCapacity:)` instead of repeatedly appending after
`reserveCapacity`.

This keeps the existing protocol behavior, dirty-rectangle reporting, and
changed-pixel counting intact. It only removes per-pixel append growth checks
from the 1920x1080 Raw decode hot path used when a VNC server sends a full Raw
frame.

## Benchmark

Command:

```bash
NARU_RUN_SIM_BENCHMARKS=1 swift test --filter RFBRawDecodeBenchmarkTests
```

Environment:

- Host: local macOS SwiftPM test run
- Frame: 1920x1080, 32-bit little-endian true-color
- Iterations: 5
- Benchmark: `testFullFrameRawFirstPaintDecodeBenchmark`

## Results

| Metric | Baseline `origin/main` | Candidate | Change |
| --- | ---: | ---: | ---: |
| Clock monotonic time | 0.327 s | 0.278 s | 15.0% lower |
| CPU time | 0.322 s | 0.276 s | 14.3% lower |
| CPU cycles | 984,769 kC | 879,447 kC | 10.7% lower |
| Retired instructions | 5,524,694 kI | 5,063,310 kI | 8.3% lower |
| Peak physical memory | 24,706 kB | 24,738 kB | flat |

The first candidate run measured 0.278 s clock / 873,459 kC. A second clean
run after removing unrelated test CPU load measured 0.278 s clock / 879,447 kC,
so the improvement was repeatable and not just a single-run outlier. An
intermediate noisy run while another worktree's `xctest` consumed CPU was
discarded and is not used as evidence.

## Correctness Checks

```bash
swift test --filter RFBRawFramebufferDecoderTests
swift test --filter RFBFramebufferDecoderTests
```

Results:

- `RFBRawFramebufferDecoderTests`: 20 passed
- `RFBFramebufferDecoderTests`: 21 passed

## Product Impact

This does not by itself make the VNC visual path pass the 10fps live gate.
It does reduce the local client decode cost for full Raw first-paint frames,
which supports the Visual Stream scorecard by reducing one piece of
client-side frame latency and CPU pressure when Raw remains the fallback.
