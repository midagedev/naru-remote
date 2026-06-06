# Bounded VNC Profile Sweep Summary - 2026-06-07

## Scope

Add a launchctl-backed `bounded-vnc-profile-sweep` runner mode for short,
privacy-safe VNC profile candidate checks. The mode imports live target
credentials from the environment, compares the fixed candidate set
`tight-first,zrle-compression-0,adaptive-good-full`, and wraps the benchmark in
a script-level wall-clock guard so a stuck live sweep ends with a fixed failure
label instead of blocking long-running work.

The runner and this artifact do not print host identity, credential values,
device identifiers, framebuffer dimensions, coordinates, pixels, byte counts,
raw helper paths, raw network errors, stimulus command text, or command output.

## Research Notes

- RFC 6143 keeps the baseline framebuffer flow request-driven: the client sends
  `FramebufferUpdateRequest` and the server replies with `FramebufferUpdate`.
  That makes request cadence and timeout behavior part of the viewer's flow
  control surface.
- TigerVNC exposes encoding, compression, quality, and color-depth controls
  because the best profile is server- and link-dependent.
- TurboVNC's H.264 study reports smaller datastreams for some VNC workloads but
  much higher CPU time, and notes that many desktop updates are small regions
  rather than full video frames. This supports keeping helper-video behind
  benchmark/permission gates while continuing VNC profile sweeps.
- Apple's frame-rate guidance says display callbacks are best effort and shaped
  by hardware/system policy, so sustained iPhone usability needs bounded,
  repeated measurements rather than assuming a requested frame rate is achieved.

Sources:

- https://www.rfc-editor.org/rfc/rfc6143
- https://tigervnc.org/doc/vncviewer.html
- https://turbovnc.org/About/H264
- https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframeraterange

## Commands

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help | rg bounded-vnc-profile-sweep
scripts/run-naru-live-benchmark.sh bounded-vnc-profile-sweep
```

## Current Result

`bounded-vnc-profile-sweep` now terminates with a privacy-safe fixed JSON
failure when the live profile sweep exceeds its wall-clock guard:

```json
{"schemaVersion":1,"mode":"bounded-vnc-profile-sweep","status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileSweep.timedOut"}
```

The runner emits that timeout label only when the wall-clock guard actually
fires; non-timeout benchmark process failures become a separate fixed failure
label instead of passing through raw command output. This is useful evidence, not a pass. Earlier direct live attempts with the full
profile set and then a single `zrle-compression-0` profile both exceeded the
interactive wait budget without producing a report. The next optimization unit
should add benchmark phase attribution for this path, so we can distinguish
stream connect, first-frame receive, stimulus launch, and incremental receive
waits before changing app streaming defaults.

## Next Actions

1. Add redacted phase-attribution for bounded profile sweeps.
2. Keep production stream defaults unchanged until a benchmark report completes
   and passes the sustained usability candidate contract.
3. Re-run after the live benchmark target is known to complete a single-profile
   stream-shape probe under the wall-clock guard.
