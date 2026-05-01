# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`  
**Created**: [DATE]  
**Status**: Draft  
**Product**: Naru Remote  
**Input**: User description: "$ARGUMENTS"

## User Scenarios & Testing *(mandatory)*

<!--
Prioritize user journeys by value. Each journey must be independently testable
and demoable. Write behavior and outcome here; implementation choices belong in
plan.md.
-->

### User Story 1 - [Brief Title] (Priority: P1)

[Describe the user, their goal, and the value in plain language.]

**Why this priority**: [Why this is first.]

**Independent Test**: [How to verify this story without completing later stories.]

**Acceptance Scenarios**:

1. **Given** [state], **When** [action], **Then** [observable outcome]
2. **Given** [state], **When** [action], **Then** [observable outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

[Describe the user, their goal, and the value in plain language.]

**Why this priority**: [Why this matters after P1.]

**Independent Test**: [How to verify this story independently.]

**Acceptance Scenarios**:

1. **Given** [state], **When** [action], **Then** [observable outcome]

---

### User Story 3 - [Brief Title] (Priority: P3)

[Describe the user, their goal, and the value in plain language.]

**Why this priority**: [Why this can follow P1/P2.]

**Independent Test**: [How to verify this story independently.]

**Acceptance Scenarios**:

1. **Given** [state], **When** [action], **Then** [observable outcome]

### Edge Cases

- [Network, protocol, focus, keyboard, paste, or permission edge case]
- [Remote OS/app compatibility edge case]
- [Privacy/security edge case]
- [Accessibility/localization edge case]

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST [specific user-visible capability]
- **FR-002**: System MUST [specific user-visible behavior]
- **FR-003**: User MUST be able to [key interaction]
- **FR-004**: System MUST [specific failure or recovery behavior]
- **FR-005**: System MUST [specific persistence or state behavior]

Use `[NEEDS CLARIFICATION: question]` only when the answer materially changes
scope, security, UX, or verification. Limit to three markers.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: [text, voice, image, file, shortcut,
  secret, agent action, or N/A]
- **IN-002**: Remote injection behavior: [user-observable behavior, not code]
- **IN-003**: Fallback behavior: [what happens when the preferred path fails]
- **IN-004**: Clipboard impact: [none, temporary, restore expected, or N/A]
- **IN-005**: User confirmation: [send, preview, approval, undo, or N/A]

### Tailnet / Connection Requirements *(mandatory if feature touches connection)*

- **TN-001**: Private-network assumption: [MagicDNS, host:port, saved profile,
  manual public endpoint, or N/A]
- **TN-002**: Diagnostics shown to user: [DNS, TCP, VNC handshake, auth,
  clipboard, helper, or N/A]
- **TN-003**: Public internet posture: [unsupported, advanced/manual, or N/A]

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing the local/remote boundary: [list]
- **SP-002**: Data retained on device: [list and retention]
- **SP-003**: Data retained on helper/remote host: [list and retention]
- **SP-004**: Sensitive actions needing approval: [list or N/A]
- **SP-005**: Logging rule: [what must not be logged]

### Key Entities *(include if feature involves data)*

- **[Entity]**: [What it represents, key attributes, and lifecycle]

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI, list at least one iPhone path (physical or simulator) before any iPad path for any user-facing UI/input scenario. iPad-only affordances (Stage Manager, multi-window, external display, hardware trackpad) belong in a separate row marked as graceful scaling, not as the primary scenario.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| [Primary scenario] | [unit / fake RFB / XCTest / XCUITest / manual device] | [iPhone / iPad-graceful / N/A] | [command, screenshot, log, or checklist] |
| [Failure scenario] | [verification type] | [device class] | [evidence] |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: [Technology-agnostic measurable outcome]
- **SC-002**: [Latency/reliability/completion target if applicable]
- **SC-003**: [User-facing quality target]
- **SC-004**: [Supportability/diagnostics target]

## Assumptions

- [Reasonable default about users, devices, remotes, or network]
- [Scope boundary]
- [External dependency or policy assumption]

## Non-Goals

- [Explicitly out-of-scope behavior]
- [Deferred feature or compatibility target]
