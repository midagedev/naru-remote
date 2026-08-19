# Codex Memory Bridge

Canonical user memory still lives under `/Users/hckim/.claude`. Use the
symlinked Codex paths below instead of creating a second copy.

## Global User Instructions

- Read `/Users/hckim/.codex/memories/claude-global.md` for durable global
  operating rules imported from Claude.

## Durable User Memory

- Read `/Users/hckim/.codex/memories/claude-user/MEMORY.md` for cross-session
  preferences and feedback.
- Files under `/Users/hckim/.codex/memories/claude-user/` are symlinked to
  `/Users/hckim/.claude/memory/`. Update the target, not a duplicate.

## Dentbird Shared Memory

- When working in `dentbird-solutions`, `ds1`, `ds2`, `ds3`, `ds4`, `ds5`, or
  `ds6`, read `/Users/hckim/.codex/memories/claude-shared/ds/MEMORY.md` first
  and then open linked docs as needed.
- Files under `/Users/hckim/.codex/memories/claude-shared/` are symlinked to
  `/Users/hckim/.claude/shared-memory/`.

## Project-Specific Memory Mirror

- Claude project memory is mirrored as symlinks under
  `/Users/hckim/.codex/memories/projects/`.
- If a matching project memory exists there, prefer it over creating a separate
  Codex-only project memory copy.

## Sync Policy

- Prefer symlinks over copied files for Claude/Codex memory.
- Project `AGENTS.md` files that already symlink to `CLAUDE.md` should stay
  as-is.

# Naru Remote Agent Instructions

Shared entry point for coding agents (Codex, Claude Code, etc.). `CLAUDE.md`
carries the same rules for Claude Code — when one changes, keep the other in
sync. Cross-feature priorities and residual work live in `NEXT_STEPS.md`;
read it before picking up work.

## Project

Naru Remote is an iPhone/iPad VNC viewer for private networks
(Tailscale-friendly). Its differentiator is reliable **local composition** of
multilingual text, voice, images, and files before sending finished input to
the remote computer, plus an optional macOS host helper (`NaruHelper`) that
unlocks Chrome-Remote-Desktop-level type-through input and a hardware-codec
video stream.

Read before architecture or implementation work: `BRANDING.md`,
`PRODUCT_SPEC.md`, `PRODUCT_RESEARCH.md`, `AGENTIC_DEVELOPMENT_METHODOLOGY.md`,
`SPEC_DRIVEN_DEVELOPMENT.md`, `.specify/memory/constitution.md`. For current
performance/parity ground truth read `PERFORMANCE_PARITY_ANALYSIS.md`.

## Spec-Driven Workflow (non-negotiable)

This repo runs Spec Kit. Treat `.specify/memory/constitution.md` as the
highest project rule after explicit user instructions.

- Do not implement a feature that lacks a `specs/<n>-<slug>/spec.md`. If a
  request would add new behavior with no spec, stop and ask, or run
  `$speckit-specify` first.
- Workflow phases: `$speckit-constitution` → `$speckit-specify` →
  `$speckit-clarify` → `$speckit-plan` → `$speckit-tasks` →
  `$speckit-implement`.
- The active feature is pinned in `.specify/feature.json`. `plan.md`,
  `research.md`, `data-model.md`, `tasks.md`, `contracts/`, and
  `quickstart.md` for that feature are authoritative — update them when
  implementation behavior changes.
- Every `specs/<n>-<slug>/spec.md` carries a **Status** line — trust it over
  roadmap prose.
- Tasks must be small and independently testable, and declare file
  ownership; parallel work only when write sets are disjoint.

<!-- SPECKIT START -->
Current active feature: `specs/015-single-row-input-dock` (keyboard-up dock
reduced from six rows / 368pt to one row; accessory keys behind `⋯`,
2026-08-19). Feature index —
001 MVP: implemented baseline · 002 Direct Keystroke: implemented v1
(PRs #28–#35) · 003 Session Experience: implemented · 004 RFB Encodings:
implemented · 005 Connection Grid Diagnostics: implemented · 006 Helper Text
Bridge: implemented v1 · 007 Helper Video Stream: implemented, real-screen
gate residual · 008 ARD Native Support: partial · 009 Live Type-Through:
implemented, physical gates residual · 010 Helper Onboarding: implemented ·
011 Simplified Input UX: implemented (two-mode dock; Direct retired as a
surface) · 012 External Pointer & Strip Completions: implemented, device
checklist residual · 013 Three-Screen Consolidation: implemented · 014
Multi-Display Focus: draft, deferred by the founder (spec only) · 015
Single-Row Input Dock: implemented (one row above the keyboard; keys behind
`⋯`; status speaks only when degraded).
<!-- SPECKIT END -->

## Architecture

Three layers, enforced by the SwiftPM target graph in `Package.swift`
(dependency rule: `iOSApp → NaruRemoteApp → NaruRemoteCore`):

- **`NaruRemoteCore`** (`NaruRemote/Sources/NaruRemoteCore/`) — pure logic,
  no SwiftUI/UIKit. Subdomains: `ConnectionHub`, `Diagnostics`, `Onboarding`,
  `RemoteInputDock` (compose draft, `TextInjectionAdapter`, Live
  type-through window/ladder, Direct keystroke), `SessionViewer`
  (`RemoteSession` state machine), `PiPWatchMode`, `VNC` (RFB boundary),
  `AppleRemoteDesktop`.
- **`NaruRemoteApp`** (`NaruRemote/App/`) — SwiftUI shell.
  `AppShell/NaruRemoteAppModel` is a `@MainActor` `ObservableObject` owning
  session lifecycle, frame streaming, PiP wiring, persistence, and text
  injection. `Features/*` are presentation-only views.
- **`NaruRemote`** (`NaruRemote/iOSApp/`) — installable entry point; only
  this layer wires concrete persistence/Keychain/PiP implementations.
- **`NaruHelper`** (`NaruHelper/Sources/`, targets in the root
  `Package.swift`) — optional macOS host helper CLI. Text bridge
  `--listen` (port 5974, Accessibility permission) and video stream
  `--video-listen` (port 5975, Screen Recording permission), HMAC-SHA256
  pairing. The MVP viewer + text path must keep working without it
  (constitution §V).

RFB capability protocols live in
`Sources/NaruRemoteCore/VNC/RFBClientBoundary.swift`. `NaruRemoteAppModel`
takes a `connectorFactory` and downcasts to the most capable protocol — this
is how production (`RFBNetworkClient`) and tests (`FakeRFBServer` fixtures +
`FakeRFBServerKit`) share one code path. Extend a boundary protocol; never
call `RFBNetworkClient` concretely from the app model.

Swift 6.0 / Swift 6 concurrency, iOS 17+, macOS 14+. Long-running RFB work
runs on `Task.detached` and re-enters `@MainActor`. Frame streams are guarded
by `streamID`/`sessionID`/`profileID` triple checks (`isCurrentStream`) —
keep that pattern in new async flows.

## Build And Test Commands

Two parallel build systems on purpose: SwiftPM for the fast inner loop,
XcodeGen for the installable app. Never hand-edit `.xcodeproj` — regenerate.
iPhone is the canonical verification target (constitution §VI); iPad is the
graceful-scaling secondary.

```bash
# Fast inner loop (Core + App + fake server + NaruHelper)
swift build
swift test

# Single test case
swift test --filter NaruRemoteCoreTests.RemoteSessionTests/testMarkFirstFrameReceived

# Regenerate the Xcode project after touching project.yml or app-target files
xcodegen generate --spec project.yml

# iPhone simulator build / test (canonical target; iOS 26.2)
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test

# iPad simulator build / test (secondary)
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build

# Deterministic fake RFB server for manual integration
swift run FakeRFBServer --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex --port 5901

# macOS host helper (dev): secrets via env indirection only, never argv
swift build -c release
NARU_HELPER_TOKEN=<secret> .build/release/NaruHelper --listen --token-env NARU_HELPER_TOKEN --port 5974

# Live-verification probes/gates against a real Mac + physical iPhone
bash scripts/run-naru-live-benchmark.sh help
```

UI work iterates via iPhone simulator screenshots judged against the spec
(founder workflow). Benchmark/probe evidence goes to `artifacts/benchmarks/`
and `artifacts/screenshots/` with privacy-safe summaries only.

## Development Rules

- Input is composed locally (constitution §I). Remote key events are a
  compatibility fallback; every input feature names its injection adapter
  and its blocked-paste/lost-focus behavior.
- Tailnet-native, public-internet-optional. No public-internet-first UX, no
  implied Tailscale affiliation — enforced in user-visible strings too.
- Verification before confidence: compiling is not done. Plans declare a
  verification matrix (XCTest, fake RFB server, XCUITest/screenshot, manual
  device) with an iPhone path before any iPad path.
- Security boundaries are product behavior: anything crossing local→remote
  defines what crosses, retention, trust boundary, permission, revocation.
  Logs avoid user-entered content by default.
- For VNC/RFB work, prove behavior with `FakeRFBServer` fixtures or
  `FakeRFBServerKit` before claiming compatibility — real servers do not
  match the spec.

## Empirical Facts That Override Assumptions

Hard-won, live-measured; do not re-litigate without new measurements:

- **Unicode X11 keysyms DO render on macOS Screen Sharing** (re-measured
  2026-07-13; reconfirmed end-to-end 2026-08-17 — live Mac, full-app E2E:
  Type "한글" and Compose "NARUSIM_한글_END" both arrived exactly, even with
  the remote Korean IME active — Unicode keysyms bypass the remote IME).
  The earlier `no-input` verdict came from two server-side loss mechanisms,
  both now understood: ① KeyEvents sent before the viewer's first
  framebuffer update are silently dropped while ScreensharingAgent
  initializes; ② screensharingd drops not-yet-injected keys when the last
  viewer disconnects. Details in `specs/011-simplified-input-ux/spec.md`.
- **ASCII keysyms are remote-IME-subject** (measured 2026-08-17): with the
  remote 2-Set Korean input source active, an ascii KeyEvent stream is
  composed into hangul — identical to a physical keyboard. Unicode-range
  keysyms insert directly regardless of the remote input source.
- **⌘V paste requires Meta_L (0xffe7)**, not Alt_L — Alt_L fails silently
  (fixed in commit `0e5d16ea`).
- **Apple Screen Sharing serves ZRLE only** and does not support
  ContinuousUpdates; its ~5.6 content-fps produce rate is the VNC framerate
  ceiling. The client pipeline is not the bottleneck
  (`PERFORMANCE_PARITY_ANALYSIS.md`); helper video is the structural path.
- **Perf instrumentation already exists**: `SessionStreamStats` + the DEBUG
  `SessionPerformanceHUDView`. Read it; don't add new timing.
- **Diagnostic exports use a fixed safe-detail catalog** — never pipe raw
  error strings or composed text into `DiagnosticExport`.
- **Credentials live in Keychain via `credentialRef`** — never on
  `ConnectionProfile` or in the file-backed store. Helper/VNC test secrets
  go through environment variables only.
- **PiP Watch is watch-only** — it must not become an input surface.
- **The Remote Input Dock is a session-only surface** — hidden pre-connect
  by design; its absence on the home screen is not a bug.
- **macOS ships bash 3.2**: in `set -u` scripts, guard empty-array expansion
  (`${ARR[@]+"${ARR[@]}"}`).
