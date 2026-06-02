# Tasks: Connection Grid, Reachability, Previews, And Collectable Diagnostics

**Branch**: `005-connection-grid-diagnostics` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Tasks are grouped by PR-sized increments. Each increment owns a small file set, includes tests, and leaves the app in a usable state.

## Increment 1 - Spec package

- **T101** Add `specs/005-connection-grid-diagnostics/spec.md`. Owns: spec file.
- **T102** Add `plan.md`, `research.md`, and `tasks.md`. Owns: docs files.
- **T103** Verify docs are committed on branch `codex/connection-grid-diagnostics-spec`. Open PR.

## Increment 2 - Grid entry and theme fixes

- **T201** `NaruRemoteColors.swift`: add adaptive tokens for card surface, card muted surface, card selected outline, status fills, and diagnostics surface. Owns: colors file.
- **T202** `ConnectionGridView.swift` (NEW): responsive `LazyVGrid` with stable card dimensions, profile display name, endpoint, host-kind warning, status badge, and preview placeholder. Owns: new file.
- **T203** `NaruRemoteAppSnapshot.swift`: add `connectionGridCards` view models derived from profiles/status/preview availability. Owns: snapshot file.
- **T204** `NaruRemoteAppShell.swift`: render grid as the default detail surface when profiles exist and no live session is active; card tap selects profile and enters session detail. Owns: shell file.
- **T205** `DiagnosticSummaryView.swift`: replace fixed light background with adaptive token; ensure labels and status icons remain readable. Owns: diagnostics view.
- **T206** `UXAuditFixtures.swift` and UI tests: add multi-profile grid fixture with status mix and no previews; run light/dark screenshots. Owns: fixture/test files.
- **T207** Verify: `swift test`; simulator screenshot/UI test for grid light/dark; PR.

## Increment 3 - Last-frame preview thumbnails

- **T301** Add `ProfilePreviewThumbnail` and `ProfilePreviewStore` protocol plus in-memory test store. Owns: preview store file.
- **T302** Add file-backed preview persistence in the iOS app layer. Owns: iOS persistence glue.
- **T303** `NaruRemoteAppModel.swift`: load previews with profiles; save a downsampled thumbnail after successful first/content frame; do not block session on save failure. Owns: model file.
- **T304** `deleteProfile(id:)`: delete preview best-effort and clear snapshot state. Owns: model file.
- **T305** `ConnectionGridView.swift`: render loaded thumbnails with stable aspect ratio; placeholder remains for missing previews. Owns: grid files.
- **T306** Tests: preview save/load/delete, profile deletion clears preview, diagnostics export excludes preview/pixel sentinels. Owns: test files.
- **T307** Verify: `swift test`; screenshot fixture with mixed previews; PR.

## Increment 4 - Launch reachability states

- **T401** Add `ProfileReachabilityState` and card mapping. Owns: Core or App snapshot file.
- **T402** Add `ReachabilityProbeCoordinator` inside `NaruRemoteAppModel` with bounded concurrency, timeout, cancellation, and separate connector instances. Owns: model file.
- **T403** Start probes after profiles load and after add/edit operations; clear state on delete. Owns: model file.
- **T404** Map success/auth-required/failure to reachable/needsPassword/unreachable via safe diagnostic stages. Owns: model file and diagnostic mapping tests.
- **T405** `ConnectionGridView.swift`: visual status badges for unknown/checking/reachable/needsPassword/unreachable with accessible labels. Owns: grid files.
- **T406** Tests: fake connector transitions, active session not disturbed, bounded cancellation, screenshot fixture with every status. Owns: tests/fixtures.
- **T407** Verify: `swift test`; grid status screenshot; PR.

## Increment 5 - Structured diagnostics collection format

- **T501** `DiagnosticExport.swift`: add `DiagnosticCollectionReport` and `renderCollectionJSON(buildVersion:now:)`. Owns: core diagnostics file.
- **T502** Define schema v2 fields: `schemaVersion`, `generatedAt`, `buildVersion`, `runID`, `profileFingerprint`, `startedAt`, `finishedAt`, `runDurationBucket`, `verdict`, and `stageRows`. Owns: diagnostics file.
- **T503** Ensure rows are generated only from `DiagnosticExport.Row` and fixed safe catalog detail. Owns: diagnostics file.
- **T504** `NaruRemoteAppModel.swift` / `DiagnosticSummaryView.swift`: share payload includes plain text plus structured JSON. Owns: app files.
- **T505** Tests: sentinel redaction for host, endpoint, credentialRef, clipboard, composed text, raw errors, pixels, thumbnails, raw latency; deterministic JSON with pinned date. Owns: test files.
- **T506** Add debug-safe context fields: target fingerprint, host kind, configured port, credential-reference presence, diagnostic trigger, probe timeout seconds, stage timestamps, and typed failure codes. Owns: diagnostics and app-model files.
- **T507** Verify: `swift test`; UI smoke for share button remains enabled only with diagnostics; PR.

## Cross-cutting Rules

- Do not persist reachability verdicts across launches as truth; refresh each launch.
- Do not include preview images or frame-derived bytes in diagnostics.
- Do not log hostnames, endpoints, passwords, clipboard text, composed text, pointer coordinates, raw latency, raw network errors, or pixels.
- iPhone simulator evidence comes before iPad evidence for every UI increment.
- Keep `.claude/` untracked and unstaged.
