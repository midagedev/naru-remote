# Remote Desktop 10fps Target Summary - 2026-06-07

## Scope

Add `iphone-remote-desktop-10fps-v1`, a stricter sustained-use benchmark
target for the user's stated expectation that the remote desktop stream must
deliver at least `10` content frames per second to feel competitive with a
smooth remote-control product.

This target is intentionally separate from `iphone-poor-network-traffic-v1`.
The older target remains useful for traffic/startup triage, while the new
target is the product-grade sustained smoothness bar.

## Target Bands

| Metric | Pass | Fail |
| --- | ---: | ---: |
| Content FPS | `>= 10` | `< 10` |
| Average update latency | `<= 100 ms` | `> 180 ms` |
| P95 update latency | `<= 180 ms` | `> 350 ms` |
| Client processing p95 | `<= 16 ms` | `> 33 ms` |
| Renderer full upload | `0` permille | `> 50` permille |
| First-frame total receive | `<= 3000 ms` | `> 8000 ms` |
| First-frame payload read | `<= 1000 ms` | `> 3000 ms` |
| First-byte wait p95 | `<= 100 ms` | `> 250 ms` |
| Payload read p95 | `<= 100 ms` | `> 250 ms` |

No host names, passwords, ports, helper executable paths, endpoints, command
lines, raw stdout/stderr, raw TCP/RFB errors, frame content, framebuffer
dimensions, coordinates, pixels, byte counts, stimulus command text, draft
text, marked text, IME state, or exact helper timings are recorded here.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help
scripts/run-naru-live-benchmark.sh glance-025-10fps-duration-probe -- --stream-shape-samples 1
swift test --filter BenchmarkStreamShapeSummaryTests/testRemoteDesktop10FPSTarget --filter BenchmarkStreamShapeSummaryTests/testSustainedUsabilityTargetSelectionIsDefaultForCliGate
scripts/run-naru-live-benchmark.sh glance-025-10fps-duration-probe
```

The extra-argument check rejects overrides so the live probe remains
repeatable.

## Current Live Result

The clean live run exited with `rc=0`.

| Field | Result |
| --- | --- |
| Wrapper status | `passed` |
| Target | `iphone-remote-desktop-10fps-v1` |
| Profile | `local-low-latency-rgb565` |
| First-frame scale | `250` permille |
| Overall decision | `fail` |
| Primary issue | `first-frame-payload-read-failed` |
| Primary constraint | `receivePath` |
| Content FPS | `1.97` |
| Average update | `508` ms |
| P95 update | `627` ms |
| First-byte wait p95 | `626` ms |
| First-frame receive | `6044` ms |
| First-frame payload read | `4926` ms |
| First-frame payload share | `850` permille |
| Renderer full upload | `0` permille |
| Samples received/content/response | `1000/1000/1000` permille |

Issue codes under the new target:

- `content-fps-failed`
- `average-update-failed`
- `p95-update-failed`
- `first-byte-wait-failed`
- `first-frame-payload-read-failed`

## Interpretation

The benchmark now reflects the user's product bar: `~2fps` is no longer a
warning candidate, it is a clear failure. The current VNC request/response path
can preserve traffic and renderer pressure, but it does not meet the sustained
smoothness target.

The next optimization unit should not try another simple profile default flip.
It should either prove that VNC update-wait/server cadence can approach the
10fps target under the fixed 0.25 shape, or pivot the product path toward the
helper-video stream for Chrome-Remote-like smoothness while keeping VNC as
input/control and fallback transport.
