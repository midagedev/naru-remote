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
