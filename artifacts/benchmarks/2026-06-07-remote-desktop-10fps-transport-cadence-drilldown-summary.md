# Remote Desktop 10fps Transport Cadence Drilldown

Date: 2026-06-07 KST

## Purpose

Reproduce the current VNC smoothness failure under one fixed local shape, then
separate request/response cadence from the ContinuousUpdates extension before
spending more work on profile-only VNC tuning.

## Research Snapshot

- RFC 6143 describes framebuffer updates as client-requested; an incremental
  request can wait until the selected area changes.
- The rfbproto/TigerVNC extension set defines ContinuousUpdates as the
  push-style transport path, but Naru must only treat it as usable after the
  server confirms support.

Sources:
- https://www.rfc-editor.org/rfc/rfc6143
- https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst

## Command

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-transport-cadence-drilldown > /tmp/naru-transport-cadence-drilldown-rerun.json
jq empty /tmp/naru-transport-cadence-drilldown-rerun.json
```

The runner holds these dimensions fixed:

- target: `iphone-remote-desktop-10fps-v1`
- profile: `local-low-latency-rgb565`
- network condition: `none`
- request region: `viewport-phone-portrait`
- first-frame mode: `visible-glance`
- visible-glance scale: `0.25`
- request pipeline depth: `1`
- duration: `12` seconds

## Result

| Candidate | Transport | Verdict | Constraint | Issue | Content FPS | Delivered FPS | Received / Content Samples | Avg Update | P95 Update |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `request-response-baseline` | `request-response` | `fail` | `receivePath` | `first-byte-wait-failed` | `5.97` | `7.05` | `85 / 72` | `132` ms | `502` ms |
| `continuous-updates-attempt` | `continuous-updates` | `fail` | `receivePath` | `probe-failed` | `0` | `0` | `0 / 0` | `0` ms | `0` ms |

Request/response still fails the 10fps gate even though payload read and
renderer upload are cheap in the same run. ContinuousUpdates fails before usable
samples on the current Mac Screen Sharing target, so it is not a promotable
default for this target class.

## Paired Helper Setup Check

The same work unit also reran the explicit helper-video setup probe:

```bash
scripts/run-naru-live-benchmark.sh screen-recording-setup > /tmp/naru-screen-recording-setup.json
```

Current fixed labels:

- capability before request: `permissionMissing`
- permission request: `notGranted`
- settings open status: `opened`
- capability after request: `permissionMissing`
- next action: `rerun-helper-readiness-sweep`

## Interpretation

This reproduces the practical failure clearly enough to choose the larger
design direction:

1. Keep request/response VNC as the input/control/fallback transport.
2. Do not spend the next unit on another VNC profile-only promotion.
3. Prioritize helper-video readiness, Screen Recording permission, and true
   H.264 capture/decode evidence for Chrome-Remote-like smoothness.
4. Keep the new drilldown as a regression gate whenever transport cadence or
   helper setup changes.

## Privacy

This artifact records only fixed mode/profile/target/transport labels,
aggregate sample counts, aggregate timings, and fixed verdict/issue labels. It
omits host identity, credentials, ports, helper paths, executable paths,
command output, raw TCP/RFB errors, coordinates, dimensions, pixels, byte
counts, stimulus command text, draft text, marked text, IME state, keysyms, and
pointer coordinates.
