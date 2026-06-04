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
- **T308** Throttle active-stream preview thumbnail generation/publish after the
  first frame so the connection grid remains recognizable without doing
  downsample work on every live content frame. Owns: app model/tests/research.
  **Done.**

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
- **T502** Define initial structured fields: `schemaVersion`, `generatedAt`, `buildVersion`, `runID`, `profileFingerprint`, `startedAt`, `finishedAt`, `runDurationBucket`, `verdict`, and `stageRows`. Owns: diagnostics file.
- **T503** Ensure rows are generated only from `DiagnosticExport.Row` and fixed safe catalog detail. Owns: diagnostics file.
- **T504** `NaruRemoteAppModel.swift` / `DiagnosticSummaryView.swift`: share payload includes plain text plus structured JSON. Owns: app files.
- **T505** Tests: sentinel redaction for host, endpoint, credentialRef, clipboard, composed text, raw errors, pixels, thumbnails, raw latency; deterministic JSON with pinned date. Owns: test files.
- **T506** Add debug-safe context fields: target fingerprint, host kind, configured port, credential-reference presence, diagnostic trigger, probe timeout seconds, stage timestamps, and typed failure codes. Owns: diagnostics and app-model files.
- **T507** Verify: `swift test`; UI smoke for share button remains enabled only with diagnostics; PR.
- **T508** Add schema v3 stream-performance summary: include safe aggregate frame counts, content/empty/timeout ratios, dirty-rectangle/change-area aggregates, duration/FPS buckets, and thermal state; exclude pixels, dimensions, coordinates, raw latency samples, and raw target identity. Owns: diagnostics/app snapshot/model/tests. **Done.**
- **T509** Bump diagnostics to schema v4 with renderer upload strategy
  aggregates: expose only full/partial upload counts, permille, and upload
  region-count maxima so hot-device reports can identify full-upload pressure
  without host, dimensions, coordinates, pixels, byte counts, or raw latency.
  Owns: diagnostics/app snapshot/model/tests. **Done.**
- **T510** Bump diagnostics to schema v5 with viewer stream power mode:
  include only the safe `balanced|power-saver` viewer setting so support can
  compare hot-device reports against the stream pacing mode, while continuing to
  exclude device power state, host, dimensions, coordinates, pixels, byte counts,
  and raw latency. Owns: diagnostics/app model/tests. **Done.**
- **T511** Bump diagnostics to schema v6 with receive-timing buckets:
  include only coarse aggregate total receive, network-read, and
  client-processing timing buckets so support can distinguish remote wait from
  local client pressure in hot/low-FPS sessions, while continuing to exclude raw
  milliseconds, raw samples, device power state, host, dimensions, coordinates,
  pixels, byte counts, and raw errors. Owns: diagnostics/app snapshot/model
  tests. **Done.**
- **T512** Bump diagnostics to schema v7 with actual RFB encoding mix counts:
  include only fixed-catalog rectangle/event counters for the encodings the
  server actually sent, so support can identify Raw-heavy sessions versus
  efficient CopyRect/Hextile/ZRLE/Tight/cursor/resize paths without payload
  bytes, dimensions, coordinates, pixels, raw timing samples, host identity, or
  raw errors. Owns: diagnostics/app snapshot/model/tests. **Done.**
- **T513** Bump diagnostics to schema v9 with safe Compose/input state:
  include only fixed-catalog draft state, direct-mode state, paste command,
  clipboard-set step, paste-command step, restore status, and duration bucket so
  physical-device reports can distinguish "clipboard did not set" from "paste
  key did not send" without composed text, clipboard text, safe-message bodies,
  host identity, coordinates, pixels, raw timing, or raw errors. Owns:
  diagnostics/app model/input tests. **Done.**
- **T514** Bump diagnostics to schema v10 with safe Compose payload encoding:
  include only `ascii|latin1|utf8ExtensionRequired` so physical-device reports
  can identify VNC clipboard compatibility risk for multilingual drafts without
  composed text, clipboard text, byte counts, safe-message bodies, host
  identity, coordinates, pixels, raw timing, or raw errors. Owns:
  diagnostics/app model/input tests. **Done.**
- **T515** Bump diagnostics to schema v11 with app frame-apply timing buckets:
  include only sample count plus coarse average/max
  `notMeasured|subFrame|interactive|lagging|stalled` buckets for MainActor
  frame-apply work so hot/low-FPS physical-device reports can distinguish
  receive/decode pressure from app-state/render-handoff pressure without raw
  milliseconds, dimensions, coordinates, pixels, byte counts, target identity,
  power state, or raw errors. Owns: diagnostics/app snapshot/model tests.
  **Done.**
- **T516** Bump diagnostics to schema v17 with safe Compose clipboard transport
  state: include only `legacyClientCutText|extendedClipboardUTF8` and
  `unknown|supported|unsupported` so physical-device reports can distinguish
  UTF-8 Extended Clipboard support from legacy fallback without composed text,
  clipboard text, byte counts, safe-message bodies, host identity, coordinates,
  pixels, raw timing, or raw errors. Owns: diagnostics/app model/RFB/input
  tests. **Done.**

## Cross-cutting Rules

- Do not persist reachability verdicts across launches as truth; refresh each launch.
- Do not include preview images or frame-derived bytes in diagnostics.
- Do not log hostnames, endpoints, passwords, clipboard text, composed text, pointer coordinates, raw latency, raw timing samples, raw network errors, or pixels.
- iPhone simulator evidence comes before iPad evidence for every UI increment.
- Keep `.claude/` untracked and unstaged.
