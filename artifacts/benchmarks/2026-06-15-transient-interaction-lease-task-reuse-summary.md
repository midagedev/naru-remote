# Transient Interaction Lease Task Reuse - 2026-06-15

## Scope

Reduce MainActor churn in the input/viewport responsiveness lane. Direct keys,
hardware keys, Compose quick keys, trackpad gestures, pointer taps, and similar
local interactions mark a short transient frame-delivery lease so visual frame
application does not starve input. The previous implementation refreshed that
lease by creating a new `UUID`, cancelling the previous task, and creating a
new `Task` for every mark.

This is a simulator/MainActor micro-performance improvement only. It is not a
physical iPhone Green claim, a live FPS claim, or a traffic/thermal promotion
result.

## Change

The transient interaction lease now stores the latest expiration instant and
keeps one sleeper task alive while the lease is active. Repeated marks update
the deadline instead of cancelling and recreating the task. Repeated marks also
skip redundant frame-delivery priority updates when the active reason set is
unchanged. When the task wakes, it re-checks the latest deadline and only clears
the transient interaction reason after the newest activity has actually expired.

## Commands

```bash
swift test --filter SessionFrameDeliveryPriorityModelTests
```

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_TRANSIENT_INTERACTION_BENCHMARK_SAMPLES=5000 \
swift test --filter TransientFrameDeliveryInteractionBenchmarkTests
```

## Results

The benchmark marks transient interaction activity 5,000 times per measured
iteration and then disconnects the model to verify the lease clears.

| Path | Clock time | CPU time | CPU cycles | CPU instructions | Physical memory | Peak physical memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Per-mark cancel/recreate task | 0.008269 s | 0.008629 s | 27306.192 kC | 79535.751 kI | 7572.698 kB | 37835.878 kB |
| Single task + deadline refresh | 0.002253 s | 0.002615 s | 8192.716 kC | 28278.129 kI | 85.197 kB | 7908.838 kB |
| Improvement | 72.8% lower | 69.7% lower | 70.0% lower | 64.4% lower | 98.9% lower | 79.1% lower |

Focused lease regressions passed: `SessionFrameDeliveryPriorityModelTests`
executed 13 tests with 0 failures.

The broader input/viewport focused suite also passed 88 selected tests:
`SessionFrameDeliveryPriorityModelTests`, `DirectKeystrokeModeTests`,
`ComposeQuickKeyModelTests`, `TrackpadModeModelTests`, and
`PointerEventTapTests`.

## Product Decision

Use a single deadline-following task for the transient interaction lease. This
is PR-worthy because the affected path runs on the MainActor during exactly the
interactions that previously felt fragile: keyboard taps, trackpad drags,
viewport gestures, and quick control keys. The change preserves the existing
"latest activity extends the lease" behavior while removing per-sample task
churn and redundant delivery-priority writes from the hot interaction path.

## Safety

This artifact records only aggregate benchmark metrics, fixed test names, and
fixed sample counts. It does not include hostnames, endpoints, credentials,
frame pixels, screenshots, pointer coordinates, keysyms, Compose text,
clipboard contents, device identifiers, raw network errors, or exact
per-interaction timing series.
