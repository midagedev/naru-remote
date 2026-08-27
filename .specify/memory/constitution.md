<!--
Sync Impact Report
Version change: 0.1.0 -> 0.2.0
Modified principles:
- (none modified in 0.2.0)
Added principles:
- VI. Phone-First, iPad-Graceful
Added sections:
- (none)
Removed sections:
- (none)
Templates requiring updates:
- .specify/templates/spec-template.md: re-check for iPhone-first language and verification primacy
- .specify/templates/plan-template.md: re-check that the verification matrix lists an iPhone path before any iPad path
- .specify/templates/tasks-template.md: re-check for iPhone-first acceptance scenarios
Deferred items:
- Template re-check (above) — pending next planning cycle

Earlier history (for reference)
Version change: template -> 0.1.0 (ratified 2026-04-29)
Modified principles:
- Template principle 1 -> I. Input Is Composed Locally
- Template principle 2 -> II. Tailnet-Native, Public-Internet-Optional
- Template principle 3 -> III. Verification Before Confidence
- Template principle 4 -> IV. Security Boundaries Are Product Behavior
- Template principle 5 -> V. Agent Work Must Be Traceable And Small
Added sections:
- Product Scope
- Required Spec Artifacts
- Development Workflow And Quality Gates
- Governance
Removed sections:
- Placeholder template sections
Templates requiring updates:
- .specify/templates/spec-template.md: updated
- .specify/templates/plan-template.md: updated
- .specify/templates/tasks-template.md: updated
Deferred items:
- None
-->

# Naru Remote Constitution

## Core Principles

### I. Input Is Composed Locally

Naru Remote is input-first, not screen-first. Every feature that enters text,
voice, images, files, shortcuts, secrets, or agent actions into a remote system
MUST treat the iPhone or iPad as the place where input is composed. Multilingual
IME assembly always happens locally: marked/composing text never crosses to the
remote (amended 2026-07-17 per founder decision D3 + spec 011). Two sanctioned
delivery paths exist once composition commits locally:

- **Type-through (default)** — committed IME units stream to the remote as they
  commit (Unicode-keysym keystroke stream on pure VNC, helper `nativeInsert`
  when paired), because live measurement (2026-07-13) proved Unicode keysyms
  render on macOS Screen Sharing. This is the primary interactive path.
- **Compose & Send** — the buffered, reviewed batch path remains the primary
  design for long-form multilingual text and anything requiring review before
  delivery.

Raw per-keystroke key events remain a compatibility fallback only; they are not
a multilingual entry design.

Feature specs MUST define the user-facing input path, the fallback path, and
what happens when the remote app blocks paste or loses focus. Plans MUST name
the injection adapter being used: VNC clipboard, keystroke stream, key events,
helper-native insert, file staging, or agent bridge.

### II. Tailnet-Native, Public-Internet-Optional

Naru Remote is optimized for private networks, especially Tailscale tailnets.
Specs MUST prefer MagicDNS names, saved private profiles, reachability checks,
and clear diagnostics over public IP-first flows. Public internet VNC access MAY
be supported, but it MUST be presented as an advanced/manual path with explicit
security warnings.

No feature may imply that Naru Remote replaces Tailscale, is an official
Tailscale product, or requires opening a VNC server to the public internet.

### III. Verification Before Confidence

Agent output is not accepted because it compiles. Every implementation plan MUST
define a verification matrix before tasks are generated. The matrix MUST include
the smallest applicable set from:

- Unit tests for pure parsing, encoding, state machines, and adapters
- Fake RFB/VNC server tests for protocol and clipboard behavior
- XCTest for iOS logic and persistence
- XCUITest or screenshot review for user-facing session UI
- macOS helper tests for paste, clipboard restore, file staging, and permissions
- Manual device checks for IME, dictation, hardware keyboard, and image paste

If a feature cannot be verified in the current environment, the task MUST mark
the residual risk and add a follow-up verification task. UI and input features
are not complete until at least one realistic iPhone/iPad path has been checked.

### IV. Security Boundaries Are Product Behavior

Security and privacy are not implementation details. Specs and plans MUST define
which data crosses from local device to remote host, how long it is retained,
and which trust boundary handles it. This applies to clipboard text, dictated
text, screenshots, images, files, secrets, saved credentials, helper channels,
tailnet inventory, logs, and agent actions.

Host helper capabilities MUST be optional, least-privilege, observable, and
revocable. Agent actions MUST be visible, interruptible, and approval-gated for
destructive or sensitive operations. Logs MUST avoid storing user-entered
content by default.

### V. Agent Work Must Be Traceable And Small

Each implementation task MUST map back to one spec requirement and one user
story. A task MUST declare file ownership, expected tests, and the observable
user outcome. Parallel agent work is allowed only when write sets are disjoint.
Shared architecture, security, protocol, and helper permission changes require
explicit planning before implementation.

Agents MUST update the relevant spec artifact when implementation changes the
behavior, limitations, or verification result. Code that diverges from the spec
is a spec failure until reconciled.

### VI. Phone-First, iPad-Graceful

Naru Remote is designed for the iPhone first. Specs and plans MUST treat
iPhone as the canonical target for layout, input, gesture, render quality,
session lifecycle, and reconnect behavior. iPad MUST work, but as a graceful
scaling of the same workflow — design pressure flows from the small screen
up, not the large screen down.

This does NOT mean iPhone use is brief intervention only. The product
explicitly supports sustained workspace use on iPhone, including
terminal-mediated workflows: a developer remoting into a desktop terminal
emulator (Ghostty, Wezterm, Alacritty), AI-coding CLIs (Codex, Claude Code,
aider, and successors), and long-running agent monitoring that consume
text-heavy framebuffers for thirty minutes to several hours. Specs MUST NOT
frame iPhone use as "confirmation surface only" or scope features as if
iPhone sessions were inherently short.

Implications enforced at review time:

- Render quality and text legibility (font sharpness, scaling accuracy,
  dirty-rectangle responsiveness, latency-to-echo) are first-class iPhone
  requirements, not iPad-only refinements.
- Compose & Send applies to AI-coding prompts, terminal commands, and
  chat-style instructions to coding agents — not only natural-language
  messaging. Korean/CJK prompt composition for AI CLIs is a primary use
  case, not an edge case.
- PiP Watch is an iPhone-class primary feature (long agent-task watch
  while the phone is used for other things), not an iPad bonus.
- Reconnect, session persistence across backgrounding, and graceful
  cellular↔Wi-Fi transitions are core requirements, not edge cases.
- iPad-only affordances (Stage Manager, multi-window, external display,
  hardware trackpad) are layered enhancements, not gates for shipping.
- Verification matrices MUST list an iPhone path before any iPad path,
  including IME, dictation, soft-keyboard typing speed, PiP enter/exit
  on a physical iPhone, and reconnect across cellular handoff.

This ordering follows the founder's lived workflow (iPhone → GUI remote
desktop → real terminal emulator and AI CLI on a private-network
machine) and the broader shift in developer tooling toward terminal-rich
AI agents that demand a fidelity beyond what iOS SSH client emulators
provide. Naru Remote competes by transporting the user's real desktop
terminal session to their pocket without breaking multilingual input —
not by being a pocket-sized SSH client.

## Product Scope

The product name is Naru Remote. The initial product is an iPhone/iPad VNC
viewer for private networks with reliable local composition of text, voice,
images, and files, plus an optional host helper and agent-ready control layer.

Primary references:

- `docs/BRANDING.md` for naming, tone, icon, color, and product language
- `docs/PRODUCT_SPEC.md` for product behavior and roadmap
- Competitive and demand research is not kept in this repository
- `docs/AGENTIC_DEVELOPMENT_METHODOLOGY.md` for agent task selection and workflow
- `docs/SPEC_DRIVEN_DEVELOPMENT.md` for the spec-driven operating model

Initial non-goals:

- Do not build a Tailscale replacement.
- Do not expose remote desktop access publicly by default.
- Do not position the first release as a full autonomous desktop agent.
- Do not require the helper for the basic VNC viewer and text path.
- Do not treat key-event typing as sufficient for multilingual input.

## Required Spec Artifacts

Every feature under `specs/` MUST contain:

- `spec.md`: user stories, functional requirements, edge cases, success
  criteria, privacy/security notes, and acceptance test matrix
- `plan.md`: architecture, chosen adapters, data flow, verification matrix, and
  constitution check
- `research.md`: decisions for unstable or risky APIs, protocols, policies, or
  library choices
- `tasks.md`: small tasks grouped by user story with explicit tests and file
  ownership

Features that touch external contracts SHOULD add `contracts/` with the relevant
protocol notes, helper IPC schema, URL schemes, App Intents, file formats, or API
contracts. Features that add persistent state MUST add `data-model.md`.

## Development Workflow And Quality Gates

Naru Remote uses Spec Kit as the repository-native SDD workflow:

1. Constitution: update this file when product or engineering rules change.
2. Specify: create or refine `spec.md` from product intent.
3. Clarify: resolve scope, security, UX, and verification gaps before planning.
4. Plan: document architecture, adapters, data flows, and tests.
5. Tasks: generate independently testable implementation tasks.
6. Implement: execute small tasks in branches/worktrees with disjoint ownership.
7. Verify: run the planned test matrix and record residual risks.
8. Reconcile: update specs when implementation reality changes.

Merge readiness requires:

- All P1 acceptance scenarios pass or are explicitly deferred.
- The verification matrix has evidence, not only assertions.
- Security/privacy notes match the implementation.
- User-facing text follows the Naru Remote brand and avoids overclaiming.
- No agent task leaves broad, unreviewed changes outside its declared write set.

## Governance

This constitution supersedes local habits when there is a conflict. Amendments
require updating this file, documenting the version change in the Sync Impact
Report, and checking the Spec Kit templates for drift.

Versioning policy:

- MAJOR: removes or redefines a core principle.
- MINOR: adds a principle, new required artifact, or new quality gate.
- PATCH: clarifies wording without changing obligations.

All new specs, plans, and task lists MUST pass the constitution check before
implementation begins. If a feature intentionally violates a principle, the plan
MUST include a complexity entry explaining why and naming the rejected simpler
alternative.

**Version**: 0.2.0 | **Ratified**: 2026-04-29 | **Last Amended**: 2026-05-01
