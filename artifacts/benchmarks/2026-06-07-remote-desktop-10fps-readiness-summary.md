# Remote Desktop 10fps Readiness Summary - 2026-06-07

## Scope

Add `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness`, a
fixed launchctl-backed dashboard for the user's 10fps remote desktop bar. The
mode combines the current VNC 10fps probe with helper-video capability,
environment preflight, external synthetic H.264, and external ScreenCaptureKit
checks.

The report is meant to answer one product question: is the current VNC visual
path still worth treating as the smooth primary path, or should the next large
unit focus on helper-video while VNC remains input/control/fallback?

No host names, passwords, ports, helper executable paths, endpoints, command
lines, raw stdout/stderr, raw TCP/RFB errors, raw OS errors, frame content,
framebuffer dimensions, coordinates, pixels, byte counts, stimulus command
text, draft text, marked text, IME state, or exact helper timings are recorded
here.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help | rg "remote-desktop-10fps-readiness"
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness -- --stream-shape-samples 1
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

The extra-argument check rejects overrides so the dashboard remains
repeatable.

## Current Live Result

The clean live readiness run exited with `rc=0`.

| Field | Result |
| --- | --- |
| Target | `iphone-remote-desktop-10fps-v1` |
| Minimum content FPS | `10` |
| Helper synthetic verdict | `pass` |
| Helper synthetic state | `healthy` |
| Helper ScreenCaptureKit verdict | `fail` |
| Helper ScreenCaptureKit permission | `missing` |
| VNC wrapper status | `passed` |
| VNC 10fps decision | `fail` |
| VNC primary issue | `first-frame-payload-read-failed` |
| VNC primary constraint | `receivePath` |
| VNC content FPS | `1.99` |
| VNC average update | `501` ms |
| VNC p95 update | `621` ms |
| VNC first-byte wait p95 | `619` ms |
| VNC first-frame payload read | `4915` ms |

VNC issue codes under the 10fps target:

- `first-frame-warning`
- `content-fps-failed`
- `average-update-failed`
- `p95-update-failed`
- `first-frame-payload-read-warning`
- `first-frame-payload-read-failed`
- `first-byte-wait-failed`

Helper ScreenCaptureKit issue codes:

- `helper-video-permission-missing`
- `helper-video-stream-unhealthy`
- `helper-video-startup-failed`
- `helper-video-sustained-stalled`
- `helper-video-fallback-observed`

## Interpretation

The current VNC request/response visual path is not close to the 10fps product
bar. It should remain valuable as control/input/fallback, but the smooth visual
path should move to helper-video unless a future VNC server-cadence probe shows
a step-change.

The external synthetic helper-video path still passes, which means the helper
transport, H.264 packet path, and safe benchmark report shape are ready enough
for the next gate. The blocker for true live helper-video is still macOS Screen
Recording permission for the stable helper app bundle.

## Next Work

1. Grant Screen Recording to the stable helper app bundle.
2. Rerun `scripts/run-naru-live-benchmark.sh helper-screen-probe`.
3. Rerun `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness`.
4. Run the true helper-video live capture benchmark and then the physical
   iPhone helper-video gate before changing product defaults.
