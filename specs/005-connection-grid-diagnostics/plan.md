# Implementation Plan: Connection Grid, Reachability, Previews, And Collectable Diagnostics

**Branch**: `005-connection-grid-diagnostics` | **Date**: 2026-06-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/005-connection-grid-diagnostics/spec.md`

## Summary

Turn Naru's saved-computer entry experience into a connection grid. The work is intentionally split into shippable PRs: first the spec, then grid/theme, preview persistence, reachability probes, and structured diagnostics. The feature is app-layer heavy, but privacy-sensitive: previews are local-only thumbnails and diagnostics are safe-catalog-only structured data.

## Constitution Check

- **I. Local-First Composition**: No change to text composition, Direct Keystroke, pointer, or clipboard input. Reachability probes do not send user content. Pass.
- **II. Tailnet-Native**: Grid cards keep MagicDNS/private endpoints as the normal path and preserve public-endpoint warnings. Pass.
- **III. Verification**: UI changes require iPhone simulator screenshots before iPad; reachability uses fake connectors; previews use store tests; diagnostics use sentinel redaction tests. Pass.
- **IV. Security Boundaries**: Preview thumbnails are local-only, deleted with profiles, and excluded from diagnostics. Structured diagnostics use fixed catalog rows, not raw errors. Pass.
- **V. Helper Optional**: No helper dependency. Pass.
- **VI. Phone-First**: iPhone grid and reachability are first-class; iPad layout scales after iPhone evidence. Pass.

No constitution violations.

## Project Structure

### Documentation

```
specs/005-connection-grid-diagnostics/
├── spec.md
├── plan.md
├── research.md
└── tasks.md
```

### Source Code

Expected edits by increment:

```
NaruRemote/App/AppShell/
├── NaruRemoteAppShell.swift          # grid as default detail entry; navigation wiring
├── NaruRemoteAppModel.swift          # reachability state, preview store wiring, share payload
├── NaruRemoteAppSnapshot.swift       # grid card rows and status snapshots
└── NaruRemoteColors.swift            # adaptive card/status tokens

NaruRemote/App/Features/ConnectionHub/
├── ConnectionGridView.swift          # new responsive grid
├── ConnectionGridCardView.swift      # card rendering, preview/placeholder/status
└── ProfileListView.swift             # keep as secondary navigation; align status language

NaruRemote/App/Features/Diagnostics/
├── DiagnosticSummaryView.swift       # adaptive background + structured share affordance
└── DiagnosticExportShareSheet.swift  # payload handoff stays system share sheet

NaruRemote/Sources/NaruRemoteCore/
├── Diagnostics/DiagnosticExport.swift          # structured JSON report
└── ConnectionHub/ProfilePreviewStore.swift     # preview store protocol/value model if kept Core-safe

NaruRemote/iOSApp/
├── UXAuditFixtures.swift             # grid, preview, reachability, light/dark fixtures
└── platform persistence glue          # file-backed preview image store if UIKit-only
```

## Sequenced Increments

1. **Spec PR** - add this feature specification, research, plan, and tasks.
2. **Grid + theme PR** - add `ConnectionGridView`, default launch into grid when profiles exist, adaptive color tokens, UX fixtures, and light/dark screenshots. Use placeholders only.
3. **Preview PR** - add preview thumbnail store, save latest frame per profile, load cards with previews, delete previews with profiles, and tests.
4. **Reachability PR** - add launch probe coordinator, per-profile reachability state, card badges, fake-connector tests, and screenshot fixture.
5. **Structured diagnostics PR** - add `DiagnosticCollectionReport` JSON, share payload composition, sentinel redaction tests, and adaptive diagnostics panel background.

Each increment must pass `swift test`. UI increments must also run the relevant simulator screenshot/UI tests and save evidence under the existing UX-audit flow.

## Technical Approach

### Grid entry

The shell should treat the grid as the default detail surface when profiles exist and no live session is active. Card tap selects a profile and transitions into the existing session viewport/detail flow. This avoids rewriting the session stack and keeps the change focused.

### Theme safety

Move fixed fills like `Color(red: 0.98, green: 0.98, blue: 0.96)` onto adaptive `NaruColors` tokens. Cards should use fixed dimensions/aspect ratios for previews, status badges, and icon wells so text cannot resize the layout.

### Preview thumbnails

The app model already observes every latest framebuffer. Add a preview sink that downscales and writes one thumbnail per profile after content frames. The Core contract should not know about UIKit image encoders unless a portable byte format is chosen; otherwise keep the protocol value type in App and the file-backed implementation in iOSApp. Tests can use an in-memory store.

### Reachability

Use a coordinator owned by `NaruRemoteAppModel` that runs bounded tasks after profiles load. Reuse existing connector/error-to-stage mapping. Auth-required without a password is a positive reachability signal (`needsPassword`). State is memory-only and refreshed each launch.

### Diagnostics

Extend `DiagnosticExport` with a structured report renderer. It should build rows from `DiagnosticExport.Row`, not from caller-provided `DiagnosticStageResult.safeTitle/safeDetail/nextAction`. `renderShareText` can remain for humans; the collection JSON should be deterministic enough for tests with injectable date/build values.

## Complexity Tracking

The highest-risk area is preview privacy, not rendering. Mitigations:

- The preview store API has no export method.
- Diagnostic export tests include pixel and thumbnail sentinels.
- Profile deletion calls preview deletion best-effort.
- Preview save failures do not block connection or session state.

The second risk is launch probes competing with real sessions. Mitigations:

- Probe connector instances are separate from active session connectors.
- Probes update only `profileReachability`, not `session`, `latestFramebuffer`, or compose state.
- Tests assert active session state remains unchanged while probes complete.
