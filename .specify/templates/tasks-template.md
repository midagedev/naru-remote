---
description: "Naru Remote task list template for feature implementation"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, and verification matrix  
**Product**: Naru Remote

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because files and dependencies are disjoint.
- **[Story]**: Maps to a user story in `spec.md`, such as `[US1]`.
- Every task MUST include exact file paths.
- Every implementation task MUST name the test or evidence that closes it.

## Phase 1: Spec & Research Readiness

**Purpose**: Ensure the agent has grounded context before writing code.

- [ ] T001 Read `BRANDING.md`, `PRODUCT_SPEC.md`, `.specify/memory/constitution.md`, and this feature's `spec.md`
- [ ] T002 Confirm all `[NEEDS CLARIFICATION]` markers are resolved or explicitly deferred
- [ ] T003 [P] Complete risky API/protocol/policy decisions in `specs/[###-feature]/research.md`
- [ ] T004 [P] Record the required verification matrix in `specs/[###-feature]/plan.md`

**Checkpoint**: No coding starts until this phase passes.

---

## Phase 2: Foundation / Test Harness

**Purpose**: Build the smallest infrastructure needed to verify behavior.

- [ ] T005 Create or update the minimal project/module structure named in `plan.md`
- [ ] T006 [P] Add unit test scaffolding for pure logic
- [ ] T007 [P] Add fake RFB/VNC server or protocol fixture when VNC behavior is touched
- [ ] T008 [P] Add XCTest/XCUITest harness when iOS UI/input behavior is touched
- [ ] T009 [P] Add helper test harness when macOS helper behavior is touched
- [ ] T010 Add documentation for running the feature checks in `specs/[###-feature]/quickstart.md`

**Checkpoint**: Verification tools exist and fail for missing implementation where applicable.

---

## Phase 3: User Story 1 - [Title] (Priority: P1) MVP

**Goal**: [User-visible outcome]

**Independent Test**: [Exact test/manual evidence from spec]

### Tests First

- [ ] T011 [P] [US1] Add failing test for [behavior] in [path]
- [ ] T012 [P] [US1] Add failing UI/manual checklist for [behavior] in [path]

### Implementation

- [ ] T013 [P] [US1] Implement [model/adapter/view] in [path]
- [ ] T014 [US1] Wire [component] to [component] in [path]
- [ ] T015 [US1] Add error/fallback handling in [path]
- [ ] T016 [US1] Update user-facing diagnostics/text in [path]

**Checkpoint**: US1 works independently and evidence is recorded.

---

## Phase 4: User Story 2 - [Title] (Priority: P2)

**Goal**: [User-visible outcome]

**Independent Test**: [Exact test/manual evidence from spec]

### Tests First

- [ ] T017 [P] [US2] Add failing test for [behavior] in [path]

### Implementation

- [ ] T018 [P] [US2] Implement [component] in [path]
- [ ] T019 [US2] Integrate with US1 without breaking US1 in [path]
- [ ] T020 [US2] Update docs/checklist evidence in [path]

**Checkpoint**: US1 and US2 both pass independently.

---

## Phase 5: User Story 3 - [Title] (Priority: P3)

**Goal**: [User-visible outcome]

**Independent Test**: [Exact test/manual evidence from spec]

### Tests First

- [ ] T021 [P] [US3] Add failing test for [behavior] in [path]

### Implementation

- [ ] T022 [P] [US3] Implement [component] in [path]
- [ ] T023 [US3] Update fallback/error handling in [path]
- [ ] T024 [US3] Update evidence in [path]

**Checkpoint**: Desired user stories pass and remain independently demoable.

---

## Phase N: Polish & Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`
- [ ] TXXX Update `spec.md` if implementation reality changed behavior
- [ ] TXXX Update `research.md` if external API/policy/library findings changed
- [ ] TXXX Security/privacy review for data crossing and logging
- [ ] TXXX Accessibility and localization review for visible UI text
- [ ] TXXX Record residual manual-device risks if the environment cannot verify them

## Dependencies & Parallelism

- Phase 1 blocks every other phase.
- Phase 2 blocks all implementation tasks.
- User stories can run in parallel only after Phase 2 and only with disjoint
  write sets.
- VNC/RFB, helper IPC, shared persistence, and security boundary files are shared
  ownership by default. Split them deliberately in `plan.md` before assigning
  parallel agents.

## Agent Handoff Notes

Each agent task prompt should include:

- Spec path
- User story and requirement IDs
- Owned files
- Forbidden files
- Exact verification command or manual evidence
- Expected final summary format
