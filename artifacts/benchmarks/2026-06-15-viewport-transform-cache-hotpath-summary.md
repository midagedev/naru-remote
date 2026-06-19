# Viewport Transform Cache Hot Path Refresh - 2026-06-15

## Scope

Re-check the helper-video viewport/input hot path after the current long-running
worktree was found behind `main` for `ViewportTransform` geometry caching.

This is a local hot-path microbenchmark and regression check. It is not a
physical iPhone Green claim, a live FPS improvement claim, or a thermal/traffic
promotion result.

## Commands

Baseline was measured by temporarily reverting only the `ViewportTransform`
cached geometry fields in the current worktree, then immediately restoring the
cached form. The current restored file is identical to `main` for
`NaruRemote/Sources/NaruRemoteCore/SessionViewer/ViewportTransform.swift`.

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES=50000 \
swift test --filter HelperVideoViewportInputHotPathBenchmarkTests/testPureViewportInputHotPathThroughputBenchmark
```

```bash
swift test --filter 'ViewportInputHotPathDriverTests|PointerGestureResolverTests|ViewportTransformTests'
```

## Results

The reverted baseline for 50,000 synthetic viewport/trackpad samples reported:

- CPU instructions retired: `46679.512 kI`
- CPU cycles: `11323.383 kC`
- clock monotonic time: `0.003319 s`

After restoring the cached `ViewportTransform` geometry from `main`, a clean
warm run reported:

- CPU instructions retired: `40968.283 kI`
- CPU cycles: `9870.136 kC`
- clock monotonic time: `0.002884 s`

Relative change:

- CPU instructions: about `12.2%` lower
- CPU cycles: about `12.8%` lower
- clock time: about `13.1%` lower on the clean warm run

The focused geometry and gesture regression suite passed with 38 selected
tests:

- `ViewportInputHotPathDriverTests`
- `PointerGestureResolverTests`
- `ViewportTransformTests`

## Product Decision

Do not open a new PR for this from the current dirty worktree: the optimized
`ViewportTransform` cache shape already exists on `main`, and the current file
now matches `main`. Treat this artifact as evidence that the local long-running
branch has been realigned with the already-merged hot-path improvement.

The next PR-worthy viewport work should improve a metric that is not already
covered by this cache, such as physical or simulator gesture long-frame ratio,
helper-video overlay cursor freshness, or zoomed trackpad hand-feel.

## Safety

This artifact contains only fixed benchmark mode names and aggregate local CPU
metric values. It omits hostnames, IP addresses, endpoints, credentials, helper
paths, device identifiers, raw VNC payloads, framebuffer pixels, screenshots,
coordinates, byte counts, Compose text, clipboard contents, and exact per-frame
timing series.
