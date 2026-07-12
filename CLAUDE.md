# CLAUDE.md

`AGENTS.md` is the canonical, current shared agent rule set for this repository.
Read it in full before work; if this shorter compatibility entry conflicts with
it, `AGENTS.md` wins.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product

Naru Remote is an iPhone/iPad VNC viewer for private networks (Tailscale-friendly). Its differentiator is reliable **local composition** of multilingual text, voice, images, and files before sending finished input to the remote computer. Required reading before architecture/implementation work: `BRANDING.md`, `PRODUCT_SPEC.md`, `PRODUCT_RESEARCH.md`, `AGENTIC_DEVELOPMENT_METHODOLOGY.md`, `SPEC_DRIVEN_DEVELOPMENT.md`, `.specify/memory/constitution.md`.

## Spec-Driven Workflow (non-negotiable)

This repo runs Spec Kit. Treat `.specify/memory/constitution.md` as the highest project rule after explicit user instructions.

- **Do not implement a feature that lacks a `specs/<n>-<slug>/spec.md`.** If a request would add new behavior with no spec, stop and ask, or use `$speckit-specify` first.
- The active feature is pinned in `.specify/feature.json` (currently `specs/005-connection-grid-diagnostics`). `plan.md`, `research.md`, `data-model.md`, `tasks.md`, `contracts/`, and `quickstart.md` for that feature are authoritative — update them when implementation behavior changes.
- Every `specs/<n>-<slug>/spec.md` carries a **Status** line — trust it over ROADMAP prose. Cross-feature priorities live in `NEXT_STEPS.md`; update it in the same PR when you finish or reprioritize work.
- `AGENTS.md` is the equivalent entry point for non-Claude agents (e.g. Codex). When rules here change, keep `AGENTS.md` in sync.
- Workflow phases: `$speckit-constitution` → `$speckit-specify` → `$speckit-clarify` → `$speckit-plan` → `$speckit-tasks` → `$speckit-implement`.
- Tasks must be small, independently testable, and declare file ownership; parallel work is allowed only when write sets are disjoint.

## Constitution Principles That Affect Code

These are enforced at review time, not just documentation:

1. **Input is composed locally.** Remote key-events are a compatibility fallback only — they must not be the primary path for multilingual/IME text. Every input feature must name its injection adapter (VNC clipboard, key events, helper-native, file staging, agent bridge) and what happens when the remote app blocks paste or loses focus.
2. **Tailnet-native, public-internet-optional.** Prefer MagicDNS/saved private profiles. Public VNC is an advanced/manual path with explicit warnings. Never imply Naru Remote replaces Tailscale or is officially affiliated.
3. **Verification before confidence.** Compiling is not done. Plans declare a verification matrix (XCTest, fake RFB server, XCUITest/screenshot, manual device). UI/input features are not complete without at least one realistic iPhone path checked (constitution §VI requires iPhone before iPad in the matrix) or an explicit residual-risk follow-up task.
4. **Security boundaries are product behavior.** For anything crossing local→remote (clipboard, dictation, screenshots, files, secrets, helper IPC, logs, agent actions), the spec/plan must define what crosses, retention, trust boundary, permission, and revocation. Logs must avoid storing user-entered content by default.
5. **Helper is optional in MVP.** The basic viewer + text path must work without `Naru Helper`. Don't add helper dependencies in MVP code.
6. **Phone-first, iPad-graceful.** iPhone is the canonical design target — small screen, soft keyboard, cellular network, and sustained terminal/AI-CLI sessions over GUI remote desktop are the baseline scenario, not brief intervention. iPad must work but as graceful scaling, not the design pivot. Verification matrices list an iPhone path before any iPad path; iPad-only affordances (Stage Manager, multi-window, external display, hardware trackpad) are layered enhancements, not gates for shipping.

## Architecture

Three layers, with module boundaries enforced by the SwiftPM target graph in `Package.swift`:

- **`NaruRemoteCore`** (`NaruRemote/Sources/NaruRemoteCore/`) — pure logic, no SwiftUI, no UIKit. Subdomains: `ConnectionHub` (profile model + file-backed store + Keychain credential boundary), `Diagnostics` (staged DNS/TCP/RFB/auth/first-frame results + safe-catalog export), `Onboarding`, `RemoteInputDock` (compose draft + `TextInjectionAdapter`), `SessionViewer` (`RemoteSession` state machine), `PiPWatchMode`, `VNC` (RFB protocol boundary).
- **`NaruRemoteApp`** (`NaruRemote/App/`) — SwiftUI shell. `AppShell/NaruRemoteAppModel` is a `@MainActor` `ObservableObject` that owns session lifecycle, frame streaming task, PiP controller wiring, profile/credential persistence, and text injection. `Features/*` are presentation-only views.
- **`NaruRemote`** (`NaruRemote/iOSApp/`) — installable app entry point. Only this layer wires concrete `FileConnectionProfilePersistence`, `KeychainConnectionCredentialStore`, and `PiPWatchPictureInPictureController` into the model.

Dependency rule: `iOSApp → NaruRemoteApp → NaruRemoteCore`. Core has no upward dependencies, which is what makes it fast to test under `swift test`.

### VNC/RFB boundaries

The RFB layer is intentionally split into capability protocols in `Sources/NaruRemoteCore/VNC/RFBClientBoundary.swift` (`RFBFirstFrameConnecting`, `RFBAuthenticatedFirstFrameConnecting`, `RFBNoAuthSessionConnecting`, `RFBAuthenticatedSessionConnecting`, `RFBFramebufferUpdating`, `RFBDamageTrackingFramebufferUpdating`, `RemoteClipboardTextClient`, and the composite `RFBStreamingClient`). `NaruRemoteAppModel` takes a `connectorFactory` injection and downcasts to the most capable protocol available — this is how production (`RFBNetworkClient`) and tests (the `FakeRFBServer` fixtures + `FakeRFBServerKit`) share the same app-model code path. When adding RFB features, extend a boundary protocol rather than calling `RFBNetworkClient` concretely.

For RFB protocol/clipboard work, prove behavior with `FakeRFBServer` fixtures or `FakeRFBServerKit` integration tests before claiming compatibility — never assume real servers behave like the spec.

## Build And Test

The repo uses **two parallel build systems** on purpose:

- **SwiftPM** (`Package.swift`) builds and tests `NaruRemoteCore`, `NaruRemoteApp`, `FakeRFBServer`, and core/app/fixture test targets. This is the fast inner loop for agent-driven model and protocol changes.
- **XcodeGen** (`project.yml`) generates `NaruRemote.xcodeproj` for the installable iOS/iPadOS bundle and `NaruRemoteUITests`. The Xcode project is regenerated; don't hand-edit `.xcodeproj` files. After changing `project.yml` or adding files that the iOS app target needs, regenerate.

```bash
# Fast inner loop (Core + App + fake server)
swift build
swift test

# Generate the iOS app project after touching project.yml or app-target files
xcodegen generate --spec project.yml

# iPhone simulator build / UI test (canonical target per constitution §VI; iOS 26.2)
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test

# iPad simulator build / UI test (graceful scaling target; iOS 26.2)
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' test

# Deterministic fake RFB server for manual integration
swift run FakeRFBServer --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex --port 5901

# Run a single XCTest case
swift test --filter NaruRemoteCoreTests.RemoteSessionTests/testMarkFirstFrameReceived
```

Toolchain: Swift 6.0 / Swift 6 concurrency, iOS 17+, macOS 14+. The app model is `@MainActor`; long-running RFB work runs on `Task.detached` and re-enters `@MainActor` to update state. Frame streams are guarded by `streamID`/`sessionID`/`profileID` triple-checks (`isCurrentStream`) — keep that pattern when adding new async flows so profile changes cancel stale streams cleanly.

## Things That Have Bitten This Codebase

- **No public-internet-first UX, no Tailscale-affiliation language.** Constitution principle II is enforced in user-visible strings too.
- **Don't treat key-event typing as sufficient for IME input.** Korean/CJK/emoji
  uses the implemented helper-native or clipboard path, never Unicode VNC
  KeyEvents on macOS Screen Sharing. The implemented Compose / Live / Direct
  modes have distinct purposes; Direct remains explicitly IME-off.
- **Diagnostic exports use a fixed safe-detail catalog**, not caller-provided strings. Don't pipe raw error messages or composed text into `DiagnosticExport`.
- **PiP Watch is watch-only.** It must not become an input surface, and the renderer/controller wiring needs physical-device verification before claims of full support.
- **Credentials live in Keychain via `credentialRef`.** Don't store passwords on `ConnectionProfile` or in the file-backed profile store.
