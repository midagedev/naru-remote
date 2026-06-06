# Glance 0.25 Profile Sweep Summary - 2026-06-07

## Scope

Add `scripts/run-naru-live-benchmark.sh glance-025-profile-sweep`, a fixed
launchctl-backed VNC-only profile comparison for the same poor-network startup
shape used by `glance-025-duration-probe`.

The sweep compares the current app-selectable stream profile candidates under
one fixed shape:

- first-frame request mode: `visible-glance`
- first-frame visible-glance scale: `0.25`
- stream transport: `request-response`
- request region: `viewport-phone-portrait`
- network condition: `constrained-cellular`
- practical target: `iphone-poor-network-traffic-v1`
- sustained phase: duration-only, `12` seconds per profile

Profiles:

- `tight-first-cursor`
- `local-low-latency-rgb565`
- `zrle-compression-0`
- `zrle-compression-0-rgb565`
- `adaptive-good-full`

No host names, passwords, ports, helper executable paths, endpoints, command
lines, raw stdout/stderr, raw TCP/RFB errors, frame content, framebuffer
dimensions, coordinates, pixels, byte counts, stimulus command text, draft
text, marked text, IME state, or exact helper timings are recorded here.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help
scripts/run-naru-live-benchmark.sh glance-025-profile-sweep -- --stream-shape-profiles tight-first
scripts/run-naru-live-benchmark.sh glance-025-profile-sweep
```

The extra-argument check rejects overrides so the sweep remains repeatable.

## Current Live Result

The clean live run exited with `rc=0` and completed all five profiles.

| Profile | Decision | Primary issue | Content FPS | Avg update | P95 update | First-frame receive | First-frame payload | Payload share | Renderer full upload | Samples received/content/response |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `tight-first-cursor` | `fail` | `probe-failed` | `0` | n/a | n/a | `27642` ms | `26503` ms | `969` | n/a | `500/500/1000` |
| `local-low-latency-rgb565` | `fail` | `first-frame-payload-read-failed` | `1.99` | `501` ms | `625` ms | `6064` ms | `4944` ms | `851` | `0` permille | `1000/1000/1000` |
| `zrle-compression-0` | `fail` | `first-frame-payload-read-failed` | `1.71` | `559` ms | `617` ms | `12510` ms | `11290` ms | `928` | `48` permille | `1000/955/955` |
| `zrle-compression-0-rgb565` | `fail` | `first-frame-payload-read-failed` | `1.73` | `525` ms | `687` ms | `6130` ms | `5009` ms | `852` | `48` permille | `1000/913/913` |
| `adaptive-good-full` | `fail` | `first-frame-payload-read-failed` | `1.65` | `548` ms | `629` ms | `12443` ms | `11220` ms | `927` | `50` permille | `1000/909/909` |

All profiles kept the first-frame request area at `19` permille and the
sustained request area at `364` permille.

## Interpretation

`local-low-latency-rgb565` remains the strongest poor-network app profile
candidate under the 0.25 visible-glance shape. It has the best content hit
rate, avoids renderer full uploads, and keeps first-frame receive time near
the single-profile duration probe result. The sweep did not find a profile that
passes the poor-network target, so the next optimization should stop looking
for a quick profile flip and instead inspect update wait timing / server
transport cadence under this fixed shape.

`tight-first-cursor` remains useful for trackpad cursor semantics, but this
run is negative evidence for making it the poor-network startup fallback: the
first-frame payload read dominated and the stream did not reach usable
sustained samples.
