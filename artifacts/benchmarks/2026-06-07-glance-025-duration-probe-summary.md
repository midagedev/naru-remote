# Glance 0.25 Duration Probe Summary - 2026-06-07

## Scope

Add `scripts/run-naru-live-benchmark.sh glance-025-duration-probe`, a fixed
launchctl-backed VNC-only probe for the current poor-network startup candidate:

- first-frame request mode: `visible-glance`
- first-frame visible-glance scale: `0.25`
- stream profile: `local-low-latency-rgb565`
- stream transport: `request-response`
- request region: `viewport-phone-portrait`
- network condition: `constrained-cellular`
- practical target: `iphone-poor-network-traffic-v1`
- sustained phase: duration-only, `12` seconds

The mode imports live VNC values from environment/`launchctl`, rejects extra
arguments, builds `VNCLiveBenchmark` once, and emits the existing privacy-safe
benchmark JSON wrapped with fixed mode/profile/scale labels.

No host names, passwords, ports, helper executable paths, endpoints, command
lines, raw stdout/stderr, raw TCP/RFB errors, frame content, framebuffer
dimensions, coordinates, pixels, byte counts, stimulus command text, draft
text, marked text, IME state, or exact helper timings are recorded here.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help
scripts/run-naru-live-benchmark.sh glance-025-duration-probe -- --stream-shape-samples 1
scripts/run-naru-live-benchmark.sh glance-025-duration-probe
```

The extra-argument check rejects overrides so the probe remains repeatable.

## Current Live Result

The clean live run exited with `rc=0`.

| Field | Result |
| --- | --- |
| Wrapper status | `passed` |
| Overall decision | `warning` |
| Primary issue | `first-frame-payload-read-warning` |
| Primary constraint | `receivePath` |
| Recommended next probe | `compareEncodingProfileGate` |
| Request cadence next probe | `inspectUpdateWaitTiming` |
| First-frame request area | `19` permille |
| Sustained request area | `364` permille |
| Received sample permille | `1000` |
| Content sample permille | `960` |
| Content response permille | `960` |
| Content FPS | `1.99` |
| Average update | `480` ms |
| P95 update | `628` ms |
| First-frame network read | `5847` ms |
| First-frame payload read | `4959` ms |
| First-frame payload read share | `848` permille |
| First-byte wait p95 | `627` ms |
| Renderer full upload permille | `0` |

## Interpretation

The `0.25` visible-glance plus `local-low-latency-rgb565` candidate is now worth
keeping as the poor-network physical-device candidate: in a longer duration-only
run it remains usable enough for a `warning` verdict, keeps first-frame traffic
to `19` permille, and avoids renderer full-upload pressure.

It is still not a product default. The remaining warnings are exactly in the
user-visible problem area: low sustained content FPS, p95 update latency, and
receive-path wait time. The next transport work should compare encoding/profile
gates and inspect update wait timing under the same fixed `0.25` shape before
changing app defaults.
