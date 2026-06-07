# Frame Application Backlog Coalescing Summary - 2026-06-07

## Scope

This increment follows the physical-iPhone freeze reports where a real VNC
connection could make gestures and keyboard input stop responding as soon as
frames began flowing. PR #354 separated the receive loop from MainActor frame
application. This follow-up bounds the frame-application backlog itself so a
busy UI does not later replay a long FIFO of stale desktop states.

The change does not promote a new VNC encoding profile, helper-video default,
request-pipeline depth, or traffic mode. It is an app-side responsiveness guard
for sustained iPhone sessions.

## Research Notes

- RFC 6143 describes the baseline RFB update flow as client-demand-driven and
  notes that, with slower clients or networks, transient framebuffer states can
  be ignored to reduce drawing and traffic pressure. A mobile viewer should
  therefore prefer current framebuffer state over preserving every stale
  intermediate state once local presentation falls behind.
- The existing live benchmark notes already found that increasing request
  pipeline depth can worsen client-processing p95 for the current candidate.
  The app should keep request depth conservative and avoid creating a second
  queue inside the UI apply path.
- Apple's Metal performance guidance emphasizes avoiding CPU/GPU stalls and
  targeting a stable frame rate when a device cannot complete all work at the
  highest refresh rate. For Naru, that maps to bounded frame apply work and
  yielding between MainActor frame applications so gestures and text input can
  interleave with visual updates.

Sources:

- https://www.rfc-editor.org/rfc/rfc6143
- https://developer.apple.com/documentation/Metal/synchronizing-cpu-and-gpu-work
- https://developer-mdn.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html

## Change

- `SessionStreamFrameApplicationQueue` now coalesces pending work to at most:
  the initial content frame needed for first-frame/session diagnostics, the
  latest content frame, and the latest server-cursor update.
- Liveness-only empty updates are dropped when content or cursor work is
  pending; when only liveness updates exist, only the latest one is retained.
- Queue waiters now receive a wake signal, not a preselected frame, so a worker
  blocked behind MainActor work selects from the latest coalesced backlog when
  it actually resumes.
- The MainActor frame-application worker yields after each frame application so
  local input and gesture events get a scheduling opportunity before the next
  queued visual update.

## Verification

Focused regression:

```bash
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests/testSessionStreamFrameApplicationQueue
```

Result: pass.

The tests prove that a lagging queue keeps sequence 1 plus the latest content
frame, and preserves the latest server-cursor update while dropping stale
content and liveness-only empty updates.

Focused app-model/snapshot suite:

```bash
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests --filter NaruRemoteAppTests.NaruRemoteAppSnapshotTests
```

Result: pass, 152 tests.

Full package suite:

```bash
swift test
```

Result: pass, 1139 tests, 13 skipped.

Live benchmark environment preflight:

```bash
scripts/run-naru-live-benchmark.sh preflight
```

Result: runnable credentials/host/port are configured through the safe
environment path, but helper-video live benchmark remains blocked by the fixed
`helper-video-permission-missing` issue code. This change is therefore verified
through unit/app-model tests, not claimed as a live FPS improvement.

## Privacy Boundary

This artifact contains no host identity, credentials, ports, command text,
draft text, marked text, keysyms, pointer coordinates, dimensions, pixels, byte
counts, raw stdout/stderr, raw network errors, or exact live timing samples.

## Next Gate

Run the app-model focused suite and full `swift test`. After merge, pair this
with the existing `tight-first-cursor` app mode on a physical iPhone session and
compare subjective freeze/gesture recovery against the previous FIFO frame
application behavior.
