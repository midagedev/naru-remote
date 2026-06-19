# VNC 10fps Readiness After Helper Wake Summary

Date: 2026-06-15 KST

## Question

After helper-video ScreenCaptureKit gates were stabilized, determine whether the
VNC visual path now has a clear 10fps promotion candidate or whether helper
video remains the primary smoothness path.

## Current Readiness

Command:

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Safe result:

- `readinessGateSummary.overallGateState`: `blockedByPhysicalIPhoneGate`
- `helperVideoGate.syntheticVerdict`: `pass`
- `helperVideoGate.sustainedSyntheticVerdict`: `pass`
- `helperVideoGate.screenCaptureVerdict`: `pass`
- `helperVideoGate.sustainedScreenCaptureVerdict`: `pass`
- `helperVideoGate.screenCaptureIssueCodes`: none
- `vnc10fpsGate.productVerdict`: `fail`
- `vnc10fpsGate.primaryIssueCode`: `payload-read-failed` in the combined
  readiness run, but repeat isolated duration probe returned to
  `first-byte-wait-failed`
- `vnc10fpsGate.primaryConstraint`: `receivePath`

Repeat isolated VNC duration probe:

```bash
scripts/run-naru-live-benchmark.sh glance-025-10fps-duration-probe
```

Safe result:

- status: `passed` wrapper, product verdict still `fail`
- content FPS: about `1.90`
- delivered FPS: about `1.99`
- p95 update: about `632` ms
- p95 first-byte wait: about `631` ms
- p95 payload read: `0` ms
- p95 client processing: about `4` ms
- primary issue: `first-byte-wait-failed`
- first frame total: about `6.1` s, still above the 5 s first-useful-paint
  Green target

## Server Cadence Probe

Command:

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-server-cadence-probe
```

Safe result:

| Candidate | Network | Request region | Startup | Content FPS | p95 first-byte | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `constrained-viewport-visible` | constrained cellular | viewport | visible glance | about `1.95` | about `630` ms | fail |
| `local-viewport-visible` | none | viewport | visible glance | about `7.33` | about `500` ms | fail |
| `constrained-viewport-full-startup` | constrained cellular | viewport | full | about `1.81` | about `618` ms | fail |
| `constrained-full-full-startup` | constrained cellular | full | full | about `1.67` | about `625` ms | fail |

The fixed next-action labels were:

- `inspect-server-update-cadence-if-first-byte-wait-persists-with-network-condition-none`
- `keep-helper-video-as-primary-smoothness-path-until-vnc-reaches-10fps`
- `do-not-promote-request-region-or-startup-mode-without-10fps-pass`

## Interpretation

No VNC configuration in this run reaches the 10fps product gate. The best local
request-response candidate is still below target at roughly 7.3fps and remains
first-byte-wait dominated. Under constrained cellular, request-region and
startup-mode changes remain around 1.7-2.0fps.

Do not spend another cycle repeating request-pipeline, request-region, or
startup-mode promotion without a new transport/server-cadence idea. The current
product path remains:

1. Keep VNC as input/control/fallback.
2. Keep helper-video as the visual smoothness candidate.
3. Unblock physical iPhone availability so the helper-video physical gate can
   run; signing/profile confusion is no longer the primary blocker when
   `xcodebuild` passes.

## Same-Day Refresh After Physical Runner Diagnostics

Command:

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Safe result:

- `readinessGateSummary.overallGateState`: `blockedByPhysicalIPhoneGate`
- `readinessGateSummary.recommendedPrimaryAction`:
  `unlock-connect-and-enable-developer-mode`
- physical iPhone gate:
  - `status`: `unavailable`
  - `buildCheckStatus`: `skipped`
  - `issueCodes`: `physical-iphone-device-unavailable`
- helper-video gate:
  - `syntheticVerdict`: `pass`
  - `sustainedSyntheticVerdict`: `pass`
  - `screenCaptureVerdict`: `pass`
  - `sustainedScreenCaptureVerdict`: `pass`
  - `screenRecordingPermission`: `granted`
- VNC 10fps gate:
  - `productVerdict`: `fail`
  - `primaryIssueCode`: `first-byte-wait-failed`
  - `primaryConstraint`: `receivePath`
  - `serverCadenceStatus`: `first-byte-wait-dominated`
  - content FPS: about `1.83`
  - first-byte p95: about `623` ms
  - payload p95: about `1` ms
  - client processing p95: about `6` ms
- transport cadence drilldown:
  - request-response candidate status: `passed`
  - request-response product verdict: `fail`
  - request-response content FPS: about `6.99`
  - ContinuousUpdates product verdict: `fail`
  - ContinuousUpdates recommended action:
    `treatContinuousUpdatesAsUnsupportedForCurrentServer`

This confirms the previous direction: do not spend another PR on request-region,
startup-glance, payload, or client-processing tuning without a new server
cadence idea. Helper-video remains the only current visual-primary path that is
ready for physical iPhone validation.

## Safety

This artifact records only fixed labels and aggregate FPS/latency buckets. It
does not include hostnames, IPs, credentials, endpoints, raw RFB errors,
dimensions, coordinates, pixels, frame payloads, byte counts, physical device
identifiers, raw xcodebuild logs, exact per-frame timings, composed text, or
clipboard contents.
