# Remote Desktop 10fps Profile Cadence Sweep - 2026-06-07

## Purpose

Add a fixed launchctl-backed live runner for comparing VNC stream profiles under
the actual product-grade remote desktop target:
`iphone-remote-desktop-10fps-v1`.

The runner keeps the 0.25 visible-glance, request-response depth 1,
viewport-phone-portrait, constrained-cellular shape fixed, then compares:

- `local-low-latency-rgb565`
- `tight-first-cursor`
- `tight-first`

This prevents older mixed-target profile artifacts from being used as evidence
for the 10fps goal.

The JSON envelope uses `mode: remote-desktop-10fps-profile-cadence-sweep`;
individual profile entries use
`mode: remote-desktop-10fps-profile-cadence-profile` so report consumers can
distinguish the sweep record from per-profile probe records.

## Commands

```sh
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help | rg "remote-desktop-10fps-profile-cadence-sweep|remote-desktop-10fps-readiness"
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-profile-cadence-sweep -- --stream-shape-profiles tight-first
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-profile-cadence-sweep > /tmp/naru-remote-desktop-10fps-profile-cadence-sweep.json
```

## Verification

- `bash -n` passed.
- Help lists `remote-desktop-10fps-profile-cadence-sweep`.
- Extra arguments are rejected with the fixed mode error.
- Live sweep exited `rc=0` and completed all three profile entries.
- The rerun after adding per-profile JSON validation also exited `rc=0`, and
  `jq empty` accepted the sweep output.

## Live Result

| Profile | Verdict | Constraint | Primary issue | Next probe | FPS | Avg update | P95 update | First-byte p95 | Payload p95 | Client p95 | First-byte share |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency-rgb565` | fail | receivePath | first-frame-payload-read-failed | compareEncodingProfileGate | 1.89 | 505 ms | 631 ms | 630 ms | 0 ms | 3 ms | 1000 |
| `tight-first-cursor` | fail | receivePath | first-frame-failed | inspectServerTransportCadence | 1.16 | 864 ms | 5600 ms | 629 ms | 1 ms | 3 ms | 1000 |
| `tight-first` | fail | receivePath | first-frame-failed | inspectServerTransportCadence | 1.16 | 861 ms | 5702 ms | 694 ms | 0 ms | 2 ms | 1000 |

Additional safe labels:

- `local-low-latency-rgb565` still has low client/render cost
  (`client p95 3 ms`, `renderer full upload 0`), so its sustained failure is
  not explained by local decode or renderer upload pressure.
- Both Tight-first variants also show low payload/client cost and
  `first-byte share 1000`, but lower FPS and much worse p95 update tails.

## Interpretation

Do not promote a new VNC profile as the path to Chrome-Remote-like smoothness.
Under the fixed 10fps target, profile changes did not move the session out of
the receive-path/first-byte-wait failure mode.

The next VNC investigation should inspect server transport cadence and update
request timing directly. Product smoothness work should continue prioritizing
true helper-video ScreenCaptureKit permission and physical iPhone helper-video
gates, while VNC remains the fallback/control/input path unless a future
server-cadence fix shows a step change.

## Privacy

The wrapper emits only fixed mode/profile/target labels, fixed issue/verdict
labels, aggregate counts, permille ratios, and aggregate timings. It does not
print host identity, credentials, ports, executable paths, command lines, raw
stdout/stderr, raw TCP/RFB errors, coordinates, dimensions, pixels, byte
counts, stimulus command text, draft text, marked text, or IME state.
