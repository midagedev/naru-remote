# Remote Desktop 10fps Server Cadence Probe Summary

Date: 2026-06-07 KST

## Purpose

Compare fixed VNC request axes under the `iphone-remote-desktop-10fps-v1`
target to determine whether the observed first-byte wait bottleneck is caused
by network conditioning, viewport-aware request regions, first-frame
visible-glance startup, or the Mac VNC server/update cadence itself.

## Runner

`scripts/run-naru-live-benchmark.sh remote-desktop-10fps-server-cadence-probe`

The runner imports live credentials from the environment/`launchctl`, builds
`VNCLiveBenchmark` once, rejects extra arguments, and runs four fixed
`local-low-latency-rgb565` candidates:

| Candidate | Network | Request Region | First Frame |
| --- | --- | --- | --- |
| `constrained-viewport-visible` | `constrained-cellular` | `viewport-phone-portrait` | `visible-glance` |
| `local-viewport-visible` | `none` | `viewport-phone-portrait` | `visible-glance` |
| `constrained-viewport-full-startup` | `constrained-cellular` | `viewport-phone-portrait` | `full` |
| `constrained-full-full-startup` | `constrained-cellular` | `full` | `full` |

All candidates use request-response transport, pipeline depth `1`, 12 second
duration-only stream-shape probes, external stimulus at 12 Hz, and schema v68
server cadence diagnosis.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh --help | rg "remote-desktop-10fps-server-cadence-probe"`
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-server-cadence-probe -- --stream-shape-samples 1`
  rejects extra arguments with a fixed mode error.
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-server-cadence-probe`
- `jq empty /tmp/naru-remote-desktop-10fps-server-cadence-probe.json`

## Live Result

All four candidates failed the 10fps target and routed to
`first-byte-wait-dominated` / `inspectServerUpdateCadence`.

| Candidate | FPS | Avg Update | P95 Update | First Byte P95 | Payload P95 | First Byte Share | Payload Share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `constrained-viewport-visible` | `1.57` | `569` ms | `910` ms | `632` ms | `425` ms | `872` | `128` |
| `local-viewport-visible` | `6.99` | `117` ms | `503` ms | `502` ms | `0` ms | `1000` | `0` |
| `constrained-viewport-full-startup` | `2.03` | `492` ms | `629` ms | `628` ms | `0` ms | `1000` | `0` |
| `constrained-full-full-startup` | `1.92` | `500` ms | `889` ms | `627` ms | `445` ms | `921` | `79` |

## Interpretation

- Removing benchmark network conditioning improves average update latency and
  FPS, but still leaves the run below 10fps and first-byte-wait dominated.
- Switching the first frame from `visible-glance` to `full` does not clear the
  sustained first-byte wait bottleneck.
- Switching sustained requests from `viewport-phone-portrait` to `full` also
  does not clear the bottleneck under constrained-cellular.
- This points away from request-region/startup-mode promotion as the path to
  Chrome-Remote-like smoothness. VNC still needs server/update-cadence
  investigation, while helper-video remains the more plausible primary
  smoothness path.

## Privacy

This artifact records only fixed mode/candidate/profile/target/network/request
labels, fixed verdict/status/action labels, aggregate millisecond summaries,
and permille shares. It omits host identity, credentials, ports, helper paths,
executable paths, command lines, raw stdout/stderr, raw TCP/RFB errors,
coordinates, dimensions, pixels, byte counts, stimulus command text, draft
text, marked text, IME state, keystroke content, and exact helper timings.
