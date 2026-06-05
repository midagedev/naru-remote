# 2026-06-05 Trackpad Edge Auto-pan Smoothness Summary

## Trigger

Physical iPhone feedback after PR #211 still reported zooming and panning as
unnatural / stepped. The highest-risk local path was zoomed trackpad auto-pan:
near the viewport reveal margin, a small high-refresh touch sample could ask
the viewport to reveal faster than the cursor moved.

## Finding

The new trace-level `PointerGestureResolverTests` reproduced the bad behavior
before the fix:

- synthetic mode: zoomed trackpad drag near the right reveal margin
- touch sample: 4 pt rightward
- old visible cursor travel: about -9.6 pt on screen

That means the user dragged right, but the visible cursor moved left because
the reveal pan outran the finger sample. On a physical phone this reads as a
snap or step, even if the remote pointer coordinate is technically correct.

## Change

- Keep central zoomed trackpad coupling unchanged.
- Cap the reveal-only auto-pan step to a fraction of the current touch sample.
- Preserve the generous cap for large deliberate drags so edge-follow still
  catches up when the user intentionally pushes toward the side.

## Verification

- `swift test --filter PointerGestureResolverTests`
  - First run with only the new test: failed as expected, proving the trace
    captured the old cursor-reversal behavior.
  - After the fix: passed, 17 tests, 0 failures.
- `swift test --filter TrackpadModeModelTests`
  - Result: passed, 11 tests, 0 failures.
- `swift test`
  - Result: passed, 771 tests, 10 skipped, 0 failures.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: build succeeded.
- `env NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=3 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmark tests, 0 failures.
  - Representative host-side measurements: full allocation/upload averaged
    about 2.6 ms monotonic time; steady-state full upload averaged about
    0.47 ms; small dirty-rect upload averaged about 0.02 ms; upload-gate skip
    averaged about 0.003 ms.
- `env NARU_RUN_SIM_BENCHMARKS=1 ... xcodebuild ... test -only-testing:NaruRemoteBenchmarkTests/SyntheticFramePipelineBenchmarkTests`
  - Result: test action succeeded, but the benchmark tests skipped because the
    shell environment did not reach the simulator test runner. Keep using the
    SwiftPM benchmark command for quick local host-side checks until the Xcode
    scheme has an explicit benchmark environment.

## Research Notes

- Apple responsiveness guidance treats foreground drawing hitches as frame
  deadline misses; for Naru, local viewport movement must stay on the compositor
  path and remain directionally consistent within each touch sample.
- `MTKView` remains on-demand (`isPaused` + `enableSetNeedsDisplay`) so remote
  frame redraws are explicitly requested instead of continuously burning GPU.
- RFC 6143 lets the client regulate incremental framebuffer requests, so remote
  freshness can be bounded while local navigation keeps touch priority.

## Remaining Risk

Physical iPhone retest is still required. This fix proves the resolver no
longer reverses visible cursor travel in the synthetic near-edge trace, but it
does not measure full finger-to-glass latency on hot hardware.
