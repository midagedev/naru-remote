# Research: Connection Grid, Reachability, Previews, And Collectable Diagnostics

**Feature**: `005-connection-grid-diagnostics`
**Date**: 2026-06-02

## Decision: Grid As Default Detail Entry, Session Flow Reused

**Decision**: When saved profiles exist, the shell renders a connection grid as the default detail surface. Tapping a card selects the profile and opens the existing session detail/session viewport.

**Rationale**: This gives the requested "grid first" experience without rewriting the already-tested session viewport, input dock, PiP, reconnect, and diagnostics wiring. It also lets wide layouts keep the current profile list as a secondary navigation aid.

**Alternatives considered**:

- Replace the entire split view with a tab/home stack. Rejected for v1 because it would churn existing iPad navigation and tests.
- Keep sidebar-only navigation and add bigger rows. Rejected because the user explicitly asked for a grid entry point with previews.

## Decision: Local Downsampled Preview Store

**Decision**: Store one local thumbnail per profile id, downsampled from the latest received framebuffer. Previews are app-private, excluded from exports, and deleted with the profile.

**Rationale**: The user asked for last screen captures in the grid. A thumbnail is enough for recognition and reduces storage/privacy exposure compared with full-resolution frame persistence.

**Alternatives considered**:

- Store the full framebuffer. Rejected due to privacy and storage cost.
- Regenerate previews only from active memory. Rejected because the grid should remain recognizable after relaunch.
- Include previews in diagnostics. Rejected by constitution privacy rules.

## Decision: Throttle Live Preview Thumbnail Generation

**Decision**: During an active stream, publish/downsample profile preview
thumbnails at most once per second after the first frame, while keeping disk
saves on the existing longer interval.

**Rationale**: The grid only needs a recognizable last-frame thumbnail, not a
live tile. Simulator frame-pipeline benchmarks show that full-frame local work
is the expensive side of the viewer path compared with same-frame/dirty-region
skips, so repeatedly downsampling a profile-card thumbnail during a sustained
session wastes CPU and can contribute to heat without improving the active
session view.

**Alternatives considered**:

- Downsample every content frame. Rejected because the session viewport already
  receives the live frame, and profile-card previews are off-path recognition
  aids.
- Only update previews on disconnect. Rejected because a crash or network drop
  would leave stale grid imagery even after a successful frame stream.

## Decision: Reachability Probes Are Memory-Only And Bounded

**Decision**: Launch probes publish memory-only states (`unknown`, `checking`, `reachable`, `needsPassword`, `unreachable`) with bounded concurrency and timeout.

**Rationale**: Reachability changes constantly. Persisting yesterday's state as truth would mislead users. Bounded probes keep startup responsive and avoid hammering many saved hosts.

**Alternatives considered**:

- Full connect to first frame for every profile. Useful when cheap, but too expensive to require for all profiles. The implementation may stop at auth-required/handshake when sufficient.
- TCP-only probe. Faster, but less accurate for VNC readiness; acceptable as later optimization but not the only proof for v1.

## Decision: Structured Diagnostics Extend Existing Safe Export

**Decision**: Add a JSON renderer to `DiagnosticExport` using only `DiagnosticExport.Row` values plus schema/build/timestamp/run metadata.

**Rationale**: Existing `DiagnosticExport` already strips caller-provided details and maps to safe catalog text. Extending that path preserves the security boundary while making support collection parseable.

**Alternatives considered**:

- Serialize `ConnectionDiagnosticRun` directly. Rejected because it contains caller-provided `safeTitle`, `safeDetail`, and `nextAction` strings that may accidentally contain sensitive values.
- Emit only text. Already exists, but hard to aggregate and filter.

## Decision: Adaptive Color Tokens For Cards And Diagnostics

**Decision**: Add or reuse `NaruColors` adaptive tokens for card surface, muted surface, status fills, and diagnostics background. Remove fixed light-only fills from affected surfaces.

**Rationale**: Existing dynamic canvas/dock tokens work, but diagnostics still has a fixed near-white background. Grid cards need stable contrast in both appearances.

**Alternatives considered**:

- Rely on SwiftUI system grouped backgrounds only. Rejected because the product already has brand tokens and status colors that need controlled semantics.

## Decision: Viewer Stream Power Mode Is Safe Diagnostic Context

**Decision**: Diagnostics schema v5 includes the viewer-selected stream power
mode as a fixed `balanced|power-saver` field. It does not include iOS Low Power
Mode or any raw power-management state.

**Rationale**: Hot-device and low-FPS reports are hard to compare unless support
knows whether the viewer was intentionally pacing the stream for a sustained
session. The app setting is user-visible and non-secret, while platform power
state remains local.

**Alternatives considered**:

- Infer mode from frame-rate buckets. Rejected because low FPS can come from the
  server, link, decoder, renderer, or user-selected pacing.
- Export iOS Low Power Mode. Rejected because support only needs the viewer
  pacing decision, not the broader device power state.

## Decision: Receive Timing Is Exported Only As Coarse Buckets

**Decision**: Diagnostics schema v6 includes aggregate receive timing as fixed
bucket labels for total receive, network read, and client processing averages
and maxima. The export does not include raw milliseconds or per-frame timing
samples.

**Rationale**: Hot iPhone reports need enough context to separate remote/server
wait from local client decode/dispatch pressure. The existing benchmark timing
split is useful, but user-shared app diagnostics need a stricter privacy shape:
coarse buckets are enough to pick the next benchmark/profile experiment while
keeping raw timing telemetry out of the support payload.

**Alternatives considered**:

- Export avg/p95 milliseconds like the live benchmark. Rejected because user
  diagnostics have a stricter minimization boundary than opt-in benchmark runs.
- Omit receive timing entirely. Rejected because support would still be unable
  to distinguish network/server stalls from client-processing pressure in
  hot-device reports.

## Decision: Actual Encoding Mix Is Safe Diagnostic Context

**Decision**: Diagnostics schema v7 includes aggregate actual RFB encoding mix
counts from the live framebuffer update path. The export carries only
fixed-catalog counters for Raw, CopyRect, Hextile, ZRLE, Tight, cursor,
desktop-size, LastRect, and end-of-continuous-updates events.

**Rationale**: `SetEncodings` is a client preference, not proof of what the
server sent. The benchmark artifact now records actual encoding mix; mirroring
that safe aggregate in user-shared diagnostics lets support distinguish
Raw-heavy sessions from sessions where the protocol is efficient and client
decode, upload, pacing, or device thermal behavior is the likelier bottleneck.

**Alternatives considered**:

- Export only the negotiated/preferred encoding list. Rejected because servers
  may ignore client preference order or choose a different encoding per update.
- Export per-frame encoding samples. Rejected because aggregate counters are
  easier to collect, safer to share, and sufficient for support triage.
