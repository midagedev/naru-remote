# Remote Desktop Readiness Gate Summary

Date: 2026-06-07 KST

## Command

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness > /tmp/naru-readiness-v2.json
jq empty /tmp/naru-readiness-v2.json
jq '.readinessGateSummary' /tmp/naru-readiness-v2.json
```

## Result

`remote-desktop-10fps-readiness` now emits schema `2` and includes a
privacy-safe `readinessGateSummary` that separates command execution success
from product readiness. The nested summary keeps its own schema `1` and emits
`parentReadinessSchemaVersion=2` so consumers can distinguish the envelope
contract from the derived summary contract.

Current local result:

- Overall gate state: `blockedByPhysicalIPhone`
- Blocked gates:
  - `physical-iphone-gate-blocked`
  - `helper-video-screen-capture-gate-blocked`
  - `vnc-10fps-product-gate-failed`
- Recommended primary action: `resolve-physical-iphone-preflight`
- Physical iPhone gate: `unavailable`, with
  `physical-iphone-device-unavailable` and
  `unlock-connect-and-enable-developer-mode`
- Helper-video gate:
  - synthetic H.264 helper transport: `pass`
  - ScreenCaptureKit helper capture: `fail`
  - Screen Recording permission: `missing`
- VNC 10fps gate:
  - wrapper status: `passed`
  - product verdict: `fail`
  - content FPS: `1.99`
  - average update: `502` ms
  - p95 update: `621` ms
  - first-byte wait p95: `618` ms
  - payload-read p95: `0` ms
  - client-processing p95: `2` ms
  - server cadence status: `first-byte-wait-dominated`

## Interpretation

This reproduces the practical failure clearly: the VNC command can run
successfully while the product 10fps target still fails. The current bottleneck
is not client decoding, payload reading, or renderer upload; it is the
server/update first-byte wait. That keeps VNC as the control/input/fallback
transport and keeps true helper-video capture/decode as the primary smoothness
path.

The summary also makes the next setup blockers explicit before more app
architecture changes:

1. Make the physical iPhone available to Xcode.
2. Grant Screen Recording permission to the stable helper app bundle.
3. Rerun the helper ScreenCaptureKit probe.
4. Run the true helper-video live capture benchmark and then the physical
   iPhone helper-video gate.

## Design Sources

- TigerVNC documents automatic adaptation of encoding/pixel format by measured
  link speed, plus a 17 ms pointer event interval. Naru should keep stream
  profile changes benchmark-backed rather than assuming one VNC profile is
  universally best.
- Apple ScreenCaptureKit exposes capture queue depth and frame interval
  controls, and Apple VideoToolbox documents low-latency H.264 encoder
  settings. The practical design remains a dual transport: VNC for control and
  fallback, helper H.264 video for smooth visual transport.

## Privacy

The new summary emits only fixed gate labels, fixed issue/action labels, small
aggregate counts, and aggregate timings. It does not emit host names,
credentials, helper paths, physical device identifiers, endpoints, framebuffer
dimensions, coordinates, pixels, byte counts, raw logs, exact helper timings,
Compose text, marked text, or IME state.
