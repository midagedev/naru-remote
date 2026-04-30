<!--
Sync Impact Report
Version change: template -> 0.1.0
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
MUST treat the iPhone or iPad as the place where input is composed, reviewed,
and confirmed. Remote key events MAY exist for compatibility, but they MUST NOT
be the primary design for multilingual text entry.

Feature specs MUST define the user-facing input path, the fallback path, and
what happens when the remote app blocks paste or loses focus. Plans MUST name
the injection adapter being used: VNC clipboard, key events, helper-native
insert, file staging, or agent bridge.

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

## Product Scope

The product name is Naru Remote. The initial product is an iPhone/iPad VNC
viewer for private networks with reliable local composition of text, voice,
images, and files, plus an optional host helper and agent-ready control layer.

Primary references:

- `BRANDING.md` for naming, tone, icon, color, and product language
- `PRODUCT_SPEC.md` for product behavior and roadmap
- `PRODUCT_RESEARCH.md` for competitive and demand research
- `AGENTIC_DEVELOPMENT_METHODOLOGY.md` for agent task selection and workflow
- `SPEC_DRIVEN_DEVELOPMENT.md` for the spec-driven operating model

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

**Version**: 0.1.0 | **Ratified**: 2026-04-29 | **Last Amended**: 2026-04-29
