# Feature Specification: Naru Helper Guided Onboarding

**Feature Branch**: `010-helper-onboarding`
**Created**: 2026-07-05
**Status**: Accepted (founder-directed 2026-07-05); implemented same pass — 5-step pairing sheet, Keychain-only secret, `--token-env` Mac snippet. Open: real single-profile helper probe (see plan.md).
**Product**: Naru Remote
**Input**: Founder goal (2026-07-05): "Implement helper onboarding — a guided in-app setup flow so a user can get NaruHelper running on their Mac and paired with a profile without reading repo docs." Today the only path to a paired helper is: read `CLAUDE.md` / spec 006 / spec 007, run `scripts/install-naru-helper-dev-app.sh` by hand, invent a pairing secret, type it into the profile editor's Helper token `SecureField`, launch `NaruHelper --listen` / `--video-listen` with the right argv/env by memory, and grant Accessibility + Screen Recording on the Mac. Every step is undocumented in-app. This feature turns that into a phone-first guided flow that generates the secret, hands the user an exact copy-able Mac snippet, walks the two macOS permissions, and verifies reachability — while keeping the pairing secret in Keychain only (constitution §IV) and keeping the helper strictly optional (constitution §V).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Guided Pairing From Zero, No Repo Docs (Priority: P1)

The founder adds (or edits) a private profile for their Mac and taps **Set up Naru Helper**. A sheet explains, honestly, what the helper unlocks (fast video, confirmed Korean text insertion, Live type-through quality) and that basic viewing already works without it. On the next step Naru generates a strong pairing secret on the phone, shows the profile fingerprint, and presents the exact commands to run on the Mac — the install script, the permission requests, and the launch line — with a separate, explicit **Copy secret** action. The user runs those on the Mac, grants the two permissions macOS prompts for, comes back, taps **Test**, and sees a fixed-catalog reachability result. When they finish, the profile has the helper enabled with the secret persisted to Keychain.

**Why this priority**: This is the entire feature. The helper is the only transport with observed Korean/CJK delivery confirmation (spec 009 / spec 006, live 2026-07-05) and the only fast-video path (spec 007); yet pairing it currently requires reading four docs and hand-assembling a shell command. The gap between "download the app" and "helper paired" is the single biggest onboarding cliff for the primary ICP (sustained AI-CLI typing from the phone). Removing repo-doc dependency is the point.

**Independent Test**: On an iPhone simulator, open the profile editor for a private-host profile, tap **Set up Naru Helper**, advance through the steps, and assert: (a) a pairing secret is generated with sufficient entropy and a stable base64url format; (b) the displayed fingerprint equals `sha256:` + lowercase hex of SHA-256 over the secret's UTF-8 bytes, and equals the fingerprint the profile editor will persist on Save; (c) the Mac snippet text contains the install script path, both permission-request flags, and the `--listen` / `--video-listen` launch lines, and contains **no** copy of the secret (only an environment-variable reference); (d) on finishing, the editor's helper toggle is enabled and the generated secret is staged for the existing Keychain save path.

**Acceptance Scenarios**:

1. **Given** the profile editor for a MagicDNS or private-address profile, **When** the user taps **Set up Naru Helper**, **Then** a step-based sheet opens on the intro step describing the benefits and stating that basic viewing works without the helper.
2. **Given** the intro step, **When** the user advances to the configure step, **Then** Naru generates a CSPRNG pairing secret, computes and displays the non-secret fingerprint, and renders a copy-able Mac setup snippet that references the secret through an environment variable rather than embedding it.
3. **Given** the configure step, **When** the user taps **Copy secret**, **Then** only the raw secret is placed on the iOS pasteboard through a distinct, explicitly-labeled action separate from **Copy commands**.
4. **Given** the user completes the flow, **When** the sheet dismisses with **Done**, **Then** the profile editor has the helper text bridge (and, if selected, helper video) enabled and the generated secret staged so a subsequent **Save** persists it via the existing `ProfileEditorCredentialUpdate` → Keychain path — never onto the profile or file store.

---

### User Story 2 — Permissions Explained In Plain Language (Priority: P1)

On the permissions step the user sees a short checklist: **Accessibility** (so the helper can insert text into the focused Mac app) and **Screen Recording** (so the helper can stream video), each with a one-line plain explanation and the note that macOS prompts for these on the Mac, not on the phone. The step tells the user which command triggers each prompt and reassures them that denying a permission only disables that one capability.

**Why this priority**: The two macOS TCC permissions are where self-serve helper setup most often stalls — the prompts appear on the Mac while the user is looking at the phone, and the failure mode (helper reachable but inserts nothing) is invisible without explanation. Constitution §IV requires the trust boundary and permission model to be product behavior, not a hidden implementation detail. Constitution §V requires the helper to be least-privilege and its capabilities individually observable.

**Independent Test**: On the permissions step, assert both permissions are listed with plain-language captions, each names the macOS-side prompt, and the copy makes clear that each capability degrades independently (no Accessibility → no native text insert; no Screen Recording → no helper video; basic VNC viewing unaffected).

**Acceptance Scenarios**:

1. **Given** the permissions step, **When** it renders, **Then** it lists Accessibility (text) and Screen Recording (video) with plain explanations and states the prompts appear on the Mac.
2. **Given** the permissions step, **When** the user reads it, **Then** it names the helper command / script flag that surfaces each macOS prompt and does not imply the phone can grant Mac permissions.
3. **Given** a user who intends to use text only, **When** they read the step, **Then** it is clear that skipping Screen Recording only disables helper video and that basic viewing needs neither permission.

---

### User Story 3 — Verify Reachability With Fixed-Catalog Status (Priority: P2)

After running the Mac commands, the user taps **Test** on the verify step. Naru checks that the Mac is reachable at the profile's host/port and shows a fixed, safe status line — reachable, unreachable, or needs-password — sourced from the diagnostic catalog, never a raw network error. The step is honest about what the test does and does not prove: it confirms the Mac is up on the tailnet; confirming that the helper handshake, pairing, and the two macOS permissions are actually live is a stronger post-save check surfaced through the profile's helper status.

**Why this priority**: A verification step that overstates its coverage is worse than none — it teaches the user to trust "green" while the helper silently can't insert. Constitution §III requires verification to be honest about residual risk. The reachability probe reuses the profile editor's existing `runProfileEditorReachabilityTest` path (already wired via the editor's `onTest` closure), so it ships today with no new model surface; the helper-handshake auto-test is defined as a named minimal API (see FR-013 / Non-Goals) rather than faked.

**Independent Test**: On the verify step with an injected test runner, tap **Test** and assert the status transitions to a checking state and then to a fixed-catalog outcome (reachable / unreachable / needs-password), that the rendered text originates from `DiagnosticMessageCatalog` (no raw error string), and that the copy discloses the test covers host reachability, not helper permission state.

**Acceptance Scenarios**:

1. **Given** the verify step with a reachable host, **When** the user taps **Test**, **Then** Naru shows a checking indicator and then a fixed reachable status with no raw network error text.
2. **Given** a host that is down or wrong, **When** the user taps **Test**, **Then** Naru shows a fixed unreachable/needs-password status from the catalog and a plain next step.
3. **Given** any verify outcome, **When** it renders, **Then** the copy states that the test confirms the Mac is reachable and that full helper verification (pairing + Accessibility + Screen Recording) is confirmed after Save via the profile's helper status. **[NEEDS CLARIFICATION: whether v1 also runs the helper-handshake probe in-flow depends on adding the single-profile awaitable helper-test API named in FR-013 and its shell wiring — until then the in-flow Test is host reachability only.]**

---

### User Story 4 — Turning The Helper Off, And Knowing What Stops (Priority: P3)

A user who paired a helper decides to stop using it, or rotates a leaked secret. The onboarding (and the profile editor) make clear where to disable or revoke the helper, that revoking clears the paired secret, and exactly what stops working when it is off (fast video, confirmed Korean insert, Live type-through fidelity) while basic viewing continues.

**Why this priority**: Constitution §IV requires helper capabilities to be revocable and the consequences legible; §V keeps the helper optional. Teardown is lower frequency than pairing, so it follows P1/P2, but it must exist so pairing is not a one-way door.

**Independent Test**: From the profile editor with a paired helper, assert the UI names how to disable (toggle off, re-save) and revoke (existing `disableHelperTextBridge` / `revokeHelperTextBridge` model affordances), and that the copy states what stops working versus what keeps working.

**Acceptance Scenarios**:

1. **Given** a paired profile, **When** the user opens setup or the editor, **Then** it explains disabling (turn the helper toggle off and Save) versus revoking (clear the paired secret) and what each does.
2. **Given** the user revokes, **When** they confirm, **Then** the paired secret reference is cleared and the profile falls back to basic viewing without losing the profile itself.

### Edge Cases

- The user advances to the configure step, then backs out without saving: the generated secret is discarded from view state and never persisted; no partial secret is written to Keychain (nothing is written until the editor's Save).
- The user regenerates the secret (advances/regenerates twice): the newest secret and its fingerprint replace the previous ones, and the Mac snippet updates; the previously copied secret is stale and will not pair.
- The user copies commands but forgets to set the secret env var on the Mac: the helper's `--listen` exits requiring `--token-env`; the reachability test may still show the host reachable (VNC), which is why the verify copy distinguishes host-up from helper-live.
- The remote is behind Tailscale and MagicDNS resolves only on the tailnet: the snippet uses the profile host verbatim; if the phone is off the tailnet the Test reports unreachable via the catalog, not a raw DNS error.
- Advanced/public host kind: the **Set up Naru Helper** entry is hidden or discouraged for `advancedManualPublicEndpoint` — the helper is a private-network capability (constitution §II); pointing a public endpoint at the helper is out of scope and must not be encouraged.
- The pasteboard copy of the secret persists in the iOS pasteboard after dismiss (OS behavior): the UI warns the secret was copied and to clear the pasteboard; Naru does not itself retain the secret after the sheet closes.
- Text-only vs. video-only setup: the user may want only one capability; the flow lets them enable only the text bridge (Accessibility) or only video (Screen Recording), and the snippet includes only the relevant launch line(s).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a **Set up Naru Helper** entry point from the profile editor for private host kinds (`magicDNS`, `privateAddress`); it MUST be hidden or clearly discouraged for `advancedManualPublicEndpoint`.
- **FR-002**: The onboarding MUST be a step-based sheet usable one-handed on iPhone, with at least: intro (benefits + optional framing), configure (secret + fingerprint + Mac snippet), permissions (Accessibility + Screen Recording), and verify (reachability test), plus a teardown/revocation pointer.
- **FR-003**: The intro step MUST state, without overclaiming, what the helper unlocks (fast video, confirmed Korean/CJK text insertion, Live type-through quality) and MUST state that basic VNC viewing works without the helper (constitution §V).
- **FR-004**: On the configure step the system MUST generate a pairing secret using a cryptographically secure random source, with a stable, copy-safe textual format and at least 256 bits of entropy.
- **FR-005**: The system MUST compute and display the profile fingerprint as `sha256:` followed by the lowercase hex SHA-256 of the secret's UTF-8 bytes, and this value MUST equal the fingerprint the profile editor persists for the same secret (single algorithm, no drift).
- **FR-006**: The system MUST present a copy-able Mac setup snippet containing: the `scripts/install-naru-helper-dev-app.sh` install invocation, the permission-request invocations (`--request-text-permission` for Accessibility, `--request-permission` for Screen Recording), and the helper launch line(s) (`--listen` for text, `--video-listen` for video) with the correct default ports (5974 text, 5975 video).
- **FR-007**: The snippet MUST reference the secret only through an environment variable (env indirection); the copy-able snippet text MUST NOT contain the secret. The fingerprint (non-secret) MAY appear literally in the snippet where the video launch requires it (`--profile-fingerprint-env`).
- **FR-008**: The system MUST provide a **Copy secret** action that is distinct and separately labeled from a **Copy commands** action, and MUST mark the secret as sensitive in the UI.
- **FR-009**: The permissions step MUST list Accessibility (text insert) and Screen Recording (video) with plain-language explanations, MUST state macOS prompts appear on the Mac, and MUST make clear each capability degrades independently and neither is needed for basic viewing.
- **FR-010**: The verify step MUST run a reachability check against the profile host/port and MUST render only fixed-catalog status text sourced from `DiagnosticMessageCatalog` (constitution §IV) — never a raw network error string.
- **FR-011**: The verify step MUST disclose that the reachability test confirms the Mac is reachable, and that full helper verification (pairing + Accessibility + Screen Recording) is confirmed after Save via the profile's helper status.
- **FR-012**: On completion, the system MUST enable the selected helper capability toggle(s) in the editor and stage the generated secret for the existing `ProfileEditorCredentialUpdate` → `model.addProfile`/`editProfile` → Keychain path; it MUST NOT write the secret onto `ConnectionProfile` or the file-backed store, and MUST NOT persist any secret before the editor's Save.
- **FR-013**: The system MUST reuse existing view-reachable model APIs for reachability (`runProfileEditorReachabilityTest` via the editor's `onTest` closure) and for helper status/teardown (`refreshProfileReachability`, `helperTextBridgeState`, `disableHelperTextBridge`, `revokeHelperTextBridge`). An in-flow **helper-handshake** auto-test (probing pairing + permissions for a single profile and awaiting a result) requires a single-profile awaitable helper-test API and shell wiring that do not exist as a view-reachable path today; v1 MUST ship the hook (optional injected closure, default absent) and degrade honestly when absent, and the missing API MUST be named for follow-up rather than faked.
- **FR-014**: The system MUST surface teardown: how to disable (helper toggle off + Save) and revoke (clear paired secret), and what stops working versus what keeps working.
- **FR-015**: The pure onboarding step/state, secret-format, fingerprint, and snippet-builder logic MUST live in `NaruRemoteCore` as value types testable under `swift test`, with no SwiftUI/UIKit dependency.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: N/A for text-to-remote. This feature composes a *pairing configuration* (secret, fingerprint, Mac snippet) on the device; it does not inject text into the remote. It is the prerequisite that unlocks the confirmed local-composition transports (spec 006 helper text bridge, spec 009 Live type-through).
- **IN-002**: Remote injection behavior: N/A (no injection). The output is a saved profile helper configuration and a Mac-side snippet the user runs.
- **IN-003**: Fallback behavior: if the user does not complete setup, the profile remains a basic VNC viewer (constitution §V); no capability is silently assumed.
- **IN-004**: Clipboard impact: the **Copy secret** and **Copy commands** actions write to the *iOS* pasteboard by explicit user action; the UI discloses the secret was copied and to clear the pasteboard. No remote/Mac clipboard is touched by this feature.
- **IN-005**: User confirmation: pairing is an explicit multi-step opt-in; the secret is only persisted on the editor's Save; teardown (disable/revoke) is user-initiated.

### Tailnet / Connection Requirements *(mandatory if feature touches connection)*

- **TN-001**: Private-network assumption: setup is offered for MagicDNS and private-address profiles; the snippet uses the profile host verbatim and assumes the Mac is on the tailnet. Public endpoints are out of scope for the entry point.
- **TN-002**: Diagnostics shown to user: reachability outcome (fixed catalog), and — post-save — the profile's helper availability state (`notConfigured` / `disabled` / `checking` / `reachable` / `unreachable` / `permissionMissing` / `revoked` / `versionUnsupported`). No raw errors, no secret, no host echoed beyond the profile the user already sees.
- **TN-003**: Public internet posture: unchanged. The flow MUST NOT encourage exposing the helper (or VNC) to the public internet (constitution §II); the helper is a tailnet-native capability.

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing the local/remote boundary: at pairing time, nothing crosses automatically. The user manually carries the pairing secret to the Mac (via the explicit copy action + their own Terminal). At runtime (later features) the secret is used only to compute HMAC-SHA256 proofs (spec 006/007); the raw secret is never sent on the wire.
- **SP-002**: Data retained on device: the pairing secret is retained in the app's Keychain under the profile's `helper-token:<uuid>` / `helper-video-token:<uuid>` reference (only after Save), never on `ConnectionProfile` or the file store. The non-secret fingerprint is stored on the profile. The onboarding's in-memory step state MUST NOT contain the raw secret beyond the transient view field; the pure `NaruRemoteCore` onboarding state MUST NOT hold the secret at all.
- **SP-003**: Data retained on helper/remote host: the Mac holds the secret only in the environment variable the user sets and (for the text `--listen` path) in the process argv; macOS holds the granted Accessibility / Screen Recording TCC entitlements for the helper app. Naru does not manage Mac-side retention; the snippet instructs env indirection to minimize exposure.
- **SP-004**: Sensitive actions needing approval: generating/copying the secret (explicit action), enabling the helper (Save), disabling/revoking (user-initiated). The secret copy MUST be a distinct action, marked sensitive.
- **SP-005**: Logging rule: logs, diagnostics, telemetry, and diagnostic exports MUST NOT contain the pairing secret, the copied snippet, the pasteboard contents, or the raw fingerprint tied to a host. Only fixed-catalog step identifiers and reachability/availability catalog states may be recorded. The fingerprint is non-secret but MUST NOT be piped into `DiagnosticExport` free-text (the export uses a fixed safe-detail catalog).

### Key Entities *(include if feature involves data)*

- **HelperOnboardingStep** — the ordered flow position (intro → configure → permissions → verify → done). Pure, `Codable`, `CaseIterable`; drives forward/back navigation and progress. Holds no secret.
- **HelperOnboardingState** — pure value type: current step, whether a secret has been generated, the non-secret fingerprint, which capabilities are being set up (text / video), and the last verification result (fixed catalog). Explicitly excludes the raw secret so it is safe to log/serialize.
- **HelperPairingMaterial** — the transient, view-held pair of (raw secret, fingerprint) produced by the CSPRNG generator; lives only in SwiftUI `@State`, cleared on dismiss, handed to the editor for the Keychain save path.
- **HelperOnboardingSnippet** — the pure builder output: the Mac command text assembled from non-secret inputs (fingerprint, host, text port 5974, video port 5975, env-var names, which capabilities). Contains no secret.
- **HelperOnboardingVerification** — fixed-catalog verify outcome (`notRun` / `checking` / `hostReachable` / `hostUnreachable` / `needsPassword` / `helperReachable` / `helperUnreachable` / `permissionMissing` / `revoked`), mapped from the reachability outcome and/or helper availability.

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI, every user-facing scenario lists an iPhone path before any iPad path; iPad-only affordances are graceful-scaling rows, not primary.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Secret generation: CSPRNG, ≥256-bit entropy, stable base64url format, distinct per call | Unit (Core) | iPhone (simulator) | `swift test` asserting length, alphabet, and non-repetition across many generations |
| Fingerprint determinism + parity with profile-editor persisted fingerprint | Unit (Core) | iPhone (simulator) | `swift test` asserting `sha256:` + lowercase hex equals the editor's algorithm for the same secret |
| Snippet builder: contains install script, both permission flags, `--listen`/`--video-listen` with ports 5974/5975; contains NO secret; references env var | Unit (Core) | iPhone (simulator) | `swift test` asserting substrings present/absent |
| Step machine: forward/back ordering, text-only vs video-only capability selection | Unit (Core) | iPhone (simulator) | `swift test` on `HelperOnboardingStep`/`HelperOnboardingState` transitions |
| Onboarding state carries no secret (privacy) | Unit (Core) | iPhone (simulator) | `swift test` encoding `HelperOnboardingState` and asserting the secret is absent |
| Entry point shows for private host, hidden/discouraged for advanced public | XCUITest / screenshot | iPhone (simulator) | Screenshot of editor with/without entry per host kind |
| Full sheet flow intro→configure→permissions→verify renders one-handed | Screenshot | iPhone (simulator) | `xcrun simctl io screenshot` of each step |
| Verify shows fixed-catalog reachable/unreachable, no raw error | XCTest (app) + screenshot | iPhone (simulator) | Injected test runner asserting catalog text; screenshot |
| Completion stages secret for Keychain save path; nothing persisted before Save | XCTest (app) | iPhone (simulator) | Assert `ProfileEditorCredentialUpdate.helperPairingSecret` set on Save, profile carries fingerprint not secret |
| Teardown pointer (disable vs revoke) present and correct | XCUITest / manual | iPhone (simulator) | Screenshot / checklist |
| Real Mac pairing end-to-end (run snippet, grant permissions, helper reachable) | Manual device | iPhone (physical) + Mac | Manual log: helper `reachable`, Korean insert observed (spec 006 probe) |
| iPad graceful scaling: sheet renders and behaves the same | Screenshot | iPad-graceful | Screenshot after iPhone paths pass |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user who has never read the repo docs can, from the profile editor, reach a state where the profile has the helper enabled and the secret persisted to Keychain, using only in-app guidance and the copy-able Mac snippet.
- **SC-002**: The fingerprint shown during onboarding matches the fingerprint persisted on Save for the same secret in 100% of cases (single-algorithm parity test).
- **SC-003**: The copy-able Mac snippet, pasted into a Terminal on a Mac that is on the tailnet with the secret exported, launches the helper such that a subsequent reachability/helper probe reports `reachable` (manual device evidence).
- **SC-004**: No pairing secret, snippet, pasteboard content, or host-linked fingerprint appears in any log, diagnostic export, or the pure onboarding state — verified by a privacy test and a diagnostic-export assertion.
- **SC-005**: The helper remains optional: with onboarding skipped or abandoned, the profile still connects and views as a basic VNC viewer with no helper dependency (constitution §V).

## Assumptions

- The confirmed setup target is macOS Screen Sharing + the `NaruHelperDev.app` dev wrapper produced by `scripts/install-naru-helper-dev-app.sh` (stable TCC identity), matching how the helper is verified live today. A signed/notarized distributable helper app is a later packaging concern; the snippet targets the current dev-app path.
- Text bridge and helper video for one profile share a single pairing secret in v1 (same Mac, same trust boundary); the profile stores them under two Keychain references but both are derived from the one generated secret and one fingerprint. Independent per-capability secrets are a possible later refinement.
- The user has Terminal access and a checkout of the Naru Remote source on the Mac (required to run the install script today). Reducing that requirement (prebuilt helper download) is out of scope.
- The reachability probe reuses the existing profile-editor `onTest` path; helper-handshake-level verification depends on a named follow-up API (FR-013).

## Non-Goals

- **A prebuilt / notarized helper installer or App Store helper distribution** — v1 targets the existing dev-app install script; packaging is a separate effort.
- **Automating the Mac side from the phone** — Naru cannot run commands or grant TCC permissions on the Mac; the flow guides the user, it does not remote-execute setup.
- **In-flow helper-handshake auto-test** — v1's Test is host reachability via the existing path; the single-profile awaitable helper-test API (probe pairing + Accessibility + Screen Recording and return a result) is named in FR-013 and left as a follow-up with shell wiring, not faked. Post-save helper status still surfaces through `helperTextBridgeState`.
- **Editing `NaruRemoteAppModel.swift`, the app shell, or `RemoteInputDock`** — this feature is view-driven and reuses existing model surface; any new model method is proposed, not implemented here.
- **Public-internet helper exposure** — out of scope and discouraged (constitution §II).
- **Per-capability distinct secrets / secret rotation UX beyond regenerate** — v1 generates one secret and offers regenerate; richer rotation is later.
- **Non-macOS hosts** — the helper and its permissions are macOS-specific; Linux/Windows helper setup is out of scope.
