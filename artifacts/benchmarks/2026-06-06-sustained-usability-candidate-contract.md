# 2026-06-06 Sustained Usability Candidate Contract

Target: `iphone-sustained-usability-v2`

## Purpose

Naru Remote is moving from small viewport, Compose, pacing, and encoding tweaks
to larger sustained-usability candidates. A candidate is now a complete shape,
not a single constant:

- stream transport and request cadence
- stream encoding profile
- startup preflight mode
- viewport zoom/pan and zoomed trackpad behavior
- Compose route and preparation behavior
- sustained thermal and active-session diagnostics

This contract defines the baseline target and the evidence required before a PR
may change production transport, encoding, preflight, pacing, or interaction
defaults.

## Baseline Goal

The practical target is a 10 minute iPhone session against a private-network Mac
that is usable for real terminal and AI CLI work:

- viewport zoom/pan should feel continuous, not stepped
- zoomed trackpad mode should keep visible cursor travel tied to finger travel
- Compose Send should be reliable for the route being tested and should expose
  fixed diagnostic blockers when it cannot safely send multilingual text
- the phone should not reach `.serious` or `.critical` thermal state
- the app should preserve a request/response fallback when server extensions
  are not confirmed

## Benchmark Gate

Run the redacted sustained v2 benchmark gate before a physical-device candidate
is promoted:

```bash
swift run VNCLiveBenchmark \
  --environment-preflight \
  --stream-shape-gate-preset sustained-v2-core \
  --ask-password \
  --json
```

Then run the live gate with the same preset after the environment preflight is
ready. A candidate is benchmark-green only when the report-level decision or
transport/cadence diagnosis routes to `runPhysicalDeviceSustainedGate`, or when
an artifact explicitly accepts a warning and explains why the warning does not
block physical testing.

The sustained v2 numeric floor remains:

- controlled-stimulus content FPS at or above 8 fps
- average update latency in the 180 ms pass band
- post-warm-up p95 update latency in the 350 ms pass band
- client-processing p95 in the 30 ms class
- 0 permille renderer full-upload pressure

Do not change production defaults from a benchmark that still routes to
`inspectContinuousUpdatesConnection`, `tuneTransportCadence`,
`compareRequestResponseEncodingProfiles`, or another remediation probe.

## Physical iPhone Gate

Run the opt-in physical sustained candidate gate for 600 seconds:

```bash
export NARU_PHYSICAL_E2E_SUSTAINED_SECONDS=600
export NARU_PHYSICAL_E2E_STREAM_POWER_MODE=balanced
export NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE=standard
export NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE=disabled
```

For a default-changing PR, compare the current baseline with the proposed
candidate using fixed labels only. The first comparison set should be:

| candidate | power | encoding | preflight | purpose |
| --- | --- | --- | --- | --- |
| current-baseline | `balanced` | `standard` | `disabled` | current production behavior |
| sustained-candidate | `balanced` | selected fixed label | selected fixed label | proposed normal default |
| thermal-candidate | `power-saver` | selected fixed label | selected fixed label | heat/battery fallback |

The physical gate is green only when the final safe diagnostic export reports
`sustainedSessionAssessment.physicalGateVerdict = pass` and the manual
hand-feel note confirms continuous viewport motion, reliable Compose behavior
for the tested route, and comfortable device heat.

`physicalGateVerdict = blocked` blocks production-default promotion even if the
detailed assessment verdict is only `warning`. Use `primaryConstraint` and
`recommendedNextProbe` to choose the next larger unit.

## Large-Unit Tracks

Until both gates are green, larger PRs should stay on one of these tracks:

- **Transport/cadence**: fix, prove, or explicitly reject the current
  ContinuousUpdates path; otherwise tune request/response cadence against the
  v43 diagnosis.
- **Encoding/profile**: compare fixed request/response candidates with the
  sustained v2 gate before changing the default profile.
- **Startup preflight**: compare `disabled` versus `one-hidden-frame` only after
  the benchmark target can graduate to the physical gate.
- **Interaction/input**: improve viewport and Compose behavior under the same
  physical gate rather than changing stream defaults.
- **Thermal/power**: compare balanced and power-saver candidate labels with the
  physical gate before making heat-related defaults.

## Merge Contract For Default Changes

A PR that changes production streaming or interaction defaults must include:

- the fixed candidate labels being promoted
- the redacted benchmark artifact and its target/verdict/next-action labels
- the physical iPhone gate result and manual hand-feel judgment
- a rollback note naming the setting, profile, or constant that restores the
  previous behavior
- updated research/tasks notes tying the evidence to `iphone-sustained-usability-v2`

## Safe Reporting

Artifacts may include fixed labels, aggregate gate counts, aggregate safe issue
counts, and pass/warning/fail decisions. Do not store host identity,
credentials, device id, port values, raw TCP/RFB errors, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw payloads, raw FPS, raw
timings, command text, command output, draft text, marked text, IME state, or
full physical-device diagnostic payloads in the repo.
