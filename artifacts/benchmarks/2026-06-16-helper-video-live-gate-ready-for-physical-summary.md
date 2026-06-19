# Helper Video Live Gate Ready For Physical - 2026-06-16

## Scope

This artifact records the current helper-video live gate state after macOS
Screen Recording permission was available for the stable development helper app
bundle. It is evidence for `specs/007-host-helper-video-stream` T031, not a
physical iPhone Green claim.

The run verifies the true helper-video live path that can be exercised without
a connected physical iPhone:

- ScreenCaptureKit permission and capture-source capability through the helper
  app bundle.
- External helper TCP streaming for synthetic, sustained synthetic,
  ScreenCaptureKit, and sustained ScreenCaptureKit helper-video probes.
- App bootstrap through `helper-tcp-to-app-model` and
  `h264-sample-buffer-factory` for 30 displayable ScreenCaptureKit frames.
- Physical iPhone preflight still runs and remains the remaining handoff gate.

## Commands

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Current retained output:

```text
/tmp/naru-helper-video-live-gate-20260616-194515.json
```

The product-level readiness gate was also refreshed:

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Current retained output:

```text
/tmp/naru-remote-desktop-10fps-readiness-20260616-194307.json
```

## Result

Helper-video live gate:

| Gate | Result |
| --- | --- |
| Screen Recording watch | `granted` |
| Helper capability | `available` |
| Synthetic helper-video probe | `pass` |
| Sustained synthetic helper-video probe | `pass` |
| ScreenCaptureKit helper-video probe | `pass` |
| Sustained ScreenCaptureKit helper-video probe | `pass` |
| App bootstrap source | `screen-capturekit` |
| App bootstrap transport path | `helper-tcp-to-app-model` |
| App bootstrap decode path | `h264-sample-buffer-factory` |
| App bootstrap requested frames | `30` |
| App bootstrap status | `passed` |
| Overall helper-video gate | `blockedByPhysicalIPhoneGate` |

Product readiness summary:

| Gate | Result |
| --- | --- |
| Overall readiness | `blockedByPhysicalIPhoneGate` |
| Helper sustained screen readiness | `readyForPhysicalGate` |
| Screen Recording permission | `granted` |
| VNC 10fps product verdict | `fail` |
| VNC content FPS | `1.894` |
| VNC primary issue | `first-byte-wait-failed` |
| VNC primary constraint | `receivePath` |
| ContinuousUpdates action | `treatContinuousUpdatesAsUnsupportedForCurrentServer` |
| Physical iPhone status | `unavailable` |
| Physical iPhone action | `unlock-connect-and-enable-developer-mode` |

## Decision

Mark T031 as complete for the non-physical true live helper-video access-unit
benchmark: the helper sender/listener is connected to the app decode path and
the ScreenCaptureKit app bootstrap gate passes for 30 displayable frames.

T030 remains open. A physical iPhone is still unavailable in this runner
context, so the product cannot claim Green or promote helper-video as a default
visual path. The next required verification is:

```bash
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

after a trusted, unlocked physical iPhone is connected and visible to the
configured development team.

## Residual Manual-Device Risk

The current evidence does not prove physical iPhone thermal behavior, touch
latency, keyboard/IME hand-feel, foreground/background transitions, or long
session stability. Those remain T030 risks and must be checked on physical
iPhone first, then iPad as graceful scaling.

## Privacy

The retained outputs and this artifact use fixed gate labels, aggregate status
labels, safe issue codes, and fixed action labels only. They do not include
helper executable paths, endpoints, credentials, auth tokens, physical device
identifiers, frame payloads, pixels, display dimensions, byte counts, raw
Xcode output, raw OS errors, composed text, keysyms, pointer coordinates, or
clipboard contents.
