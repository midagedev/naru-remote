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

## Project

This repository is the planning and implementation workspace for `Naru Remote`,
an iPhone/iPad VNC viewer for private networks. Its differentiator is reliable
local composition of multilingual text, voice, images, and files before sending
the finished input to a remote computer.

Read these documents before architecture or implementation work:

- `BRANDING.md`
- `PRODUCT_SPEC.md`
- `PRODUCT_RESEARCH.md`
- `AGENTIC_DEVELOPMENT_METHODOLOGY.md`
- `SPEC_DRIVEN_DEVELOPMENT.md`
- `.specify/memory/constitution.md`

## Spec-Driven Workflow

Use Spec Kit for feature work:

- `$speckit-constitution`: update governing rules.
- `$speckit-specify`: create or revise a feature spec.
- `$speckit-clarify`: resolve ambiguous scope/security/UX questions.
- `$speckit-plan`: generate technical plan and design artifacts.
- `$speckit-tasks`: generate executable tasks.
- `$speckit-implement`: implement only after spec, plan, and tasks are ready.

<!-- SPECKIT START -->
Current active feature: `specs/002-direct-keystroke-mode` (spec only — plan / tasks not yet generated; the prior MVP feature `specs/001-naru-remote-mvp/` remains the reference baseline).
<!-- SPECKIT END -->

## Development Rules

- Do not implement a feature that lacks a `specs/*/spec.md`.
- Treat `.specify/memory/constitution.md` as the highest project rule after
  explicit user instructions.
- Keep tasks small and independently testable; declare file ownership when
  delegating or parallelizing.
- For iOS/UI/input work, include XCTest, XCUITest, fake-server, screenshot, or
  manual-device verification as appropriate.
- For VNC/RFB work, use protocol fixtures or fake servers before claiming
  compatibility.
- For helper or agent bridge work, specify trust boundaries, permissions,
  revocation, logging, and failure behavior before coding.
- Avoid public-internet-first UX and avoid implying official Tailscale
  affiliation.

## Build And Test Commands

Current foundation is a Swift Package with `NaruRemoteCore` and
`NaruRemoteApp` shell targets plus an XcodeGen-generated installable iOS/iPadOS
app target.

- Build and unit tests: `swift test`
- Package build only: `swift build`
- Generate Xcode project: `xcodegen generate --spec project.yml`
- iPad simulator app build: `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`
- iPad simulator UI test: `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' test`
- Fake RFB server: `swift run FakeRFBServer --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex --port 5901`

Remaining command categories:

- macOS helper tests
- lint/format checks
