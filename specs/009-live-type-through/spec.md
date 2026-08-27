# Feature Specification: Live Type-Through Input Mode

**Feature Branch**: `009-live-type-through`  
**Created**: 2026-07-05  
**Status**: Implemented (clarifications resolved 2026-07-05 via founder decisions D1/D2/D3; T001–T020 + review fixes TR01–TR04). Reconciled 2026-07-12; residual: physical gates T021–T024, and D3 default-path promotion awaits gate pass.
**Product**: Naru Remote  
**Input**: Founder goal (2026-07-05, `docs/PERFORMANCE_PARITY_ANALYSIS.md` §4.3, §5 Track B): "Chrome Remote Desktop 수준의 사용성 — 특히 compose 입력이 정말 잘 되는 상태." The batch Compose & Send model pays a 1–1.3 s+ per-sentence silence budget (local settle + clipboard settle + server cadence + an "unknown" result banner) that CRD does not. CRD's compose feels good because it is **type-through**: locally IME-composed units are injected into the host natively as they commit, with no separate Send. This feature adds the type-through peer to Compose & Send, built on the transports proven live on 2026-07-05: helper text bridge `nativeInsert` delivered Hangul to a controlled target (`observed-inserted` / `matched`); VNC `KeyEvent` with X11 Unicode keysyms did **not** arrive on macOS Screen Sharing (`no-input`); VNC clipboard + paste works but is batch-only with a 0.30 s settle.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Korean Prompt Lands As You Type, No Send Tap (Priority: P1)

The founder is on iPhone in an active VNC session to their own Mac, focused on a terminal running an AI coding CLI. They switch the Remote Input Dock to Live type-through mode and type a mixed Korean/English prompt on the phone's native keyboard. Each time a Hangul syllable (or word/punctuation) finalizes out of IME composition, that committed unit appears at the remote insertion point within a fraction of a second. There is no Send button; the composition simply flows through as it commits.

**Why this priority**: This is the entire point of the feature and the founder's top-priority track (`docs/PERFORMANCE_PARITY_ANALYSIS.md` §5 Track B, "사용자 최우선"). It is the CRD-parity path for the primary ICP scenario — sustained, conversational, multilingual typing into terminals and AI CLIs from the phone. The batch model's per-sentence silence budget is precisely what makes that scenario feel un-smooth.

**Independent Test**: With a paired reachable helper (or `FakeRFBServerKit` + fake helper endpoint), switch the dock to Live mode and type a Korean word using an IME. Assert that (a) no bytes are emitted while text is in the marked/composing state, (b) one helper `nativeInsert` request carrying only the committed unit is emitted at each composition-commit boundary, and (c) no VNC `ClientCutText`, paste key event, or Unicode `KeyEvent` is emitted for that unit. The `helper-text-observed-probe` (unicode-hangul) reports `observed-inserted` / `matched` at the controlled target.

**Acceptance Scenarios**:

1. **Given** an active VNC session to a profile with a paired reachable helper and Live mode selected, **When** the user types a Korean syllable and it commits out of IME composition, **Then** Naru delivers only the committed syllable through the helper text bridge and reflects a per-unit "delivered" status, without a Send tap and without touching the VNC clipboard.
2. **Given** Live mode with text mid-composition (marked text present), **When** the user has not yet committed the syllable, **Then** Naru sends nothing to the remote (Hangul assembly stays local per constitution §I); only the local mirror shows the in-progress composition.
3. **Given** Live mode is active, **When** the user types a run of ASCII characters, **Then** each committed run is delivered through the same primary helper path (not per-raw-keystroke), preserving order at the remote.

---

### User Story 2 — Three Coexisting Input Modes, One-Tap Switch (Priority: P1)

The user alternates between writing a long reviewed Korean message (batch Compose & Send), conversational live typing into a shell/CLI (Live type-through), and driving a TUI with terminal keys like Tab / Ctrl-C / arrows (Direct Keystroke, spec 002). All three live in the Remote Input Dock and switch in one tap, and switching never corrupts the remote or silently loses local work.

**Why this priority**: Live type-through must not cannibalize the batch path — constitution §I keeps Compose & Send as the reviewed multilingual default, and §I's "MAY" exception keeps Direct Keystroke for raw terminal keys. The three modes are complementary; the switch must be legible and non-destructive, or users will distrust Live mode.

**Independent Test**: From an active session, cycle Compose → Live → Direct → Compose. Assert the Compose partial draft survives the round trip (spec 002 FR-011 pattern), Direct sticky-modifier state clears on exit (spec 002 FR-012), and switching out of Live mode seals its current editing window (committed text stays at the remote, marked/uncommitted text is dropped, and no retroactive delete crosses the seal).

**Acceptance Scenarios**:

1. **Given** a partial Compose & Send draft exists, **When** the user switches to Live mode and back, **Then** the Compose draft is restored exactly and was never sent.
2. **Given** Live mode with an open editing window and text mid-composition, **When** the user switches to Compose or Direct mode, **Then** the marked text is discarded, the already-committed text remains at the remote, and no delete op is sent across the seal.
3. **Given** the Remote Input Dock, **When** the user picks a mode, **Then** the active mode is switchable in one tap, the active mode is visibly indicated, and each mode carries its own persistent disclosure (Live: transport/latency badge; Direct: "IME off" badge per spec 002 FR-010).

---

### User Story 3 — Correction And Line Boundaries Behave (Priority: P1)

While live-typing, the user makes a typo, backspaces to fix it, and presses Return to submit a shell line. Corrections to text they are still editing update the remote to match; a Return flushes and closes the line so the next line starts clean.

**Why this priority**: Type-through is unusable if backspace desyncs the phone from the remote or corrupts remote content. Commit-unit and correction semantics are the load-bearing correctness contract of the whole mode.

**Independent Test**: With a fake helper recorder, type `hte`, backspace once, type `e`, then Return. Assert the emitted operation sequence reconciles the remote editing window to `the\n` using minimal insert/delete-back operations delivered strictly in order, and that the window seals on Return with a fresh window opening after.

**Acceptance Scenarios**:

1. **Given** an open Live editing window with committed text present at the remote, **When** the user backspaces within that window, **Then** Naru reconciles the remote by emitting the minimal delete-back operation(s) needed, in strict order relative to prior inserts. **Resolved 2026-07-05 (founder decision D1)**: a backspace that reaches text already delivered to the remote DOES emit a remote delete, implemented as remote `BackSpace` key events (X11 keysym `0xff08`) sent through the existing VNC `KeyEvent` lane (the same lane Direct Keystroke uses) — one `BackSpace` per grapheme to remove from the window mirror. v1 does NOT extend the spec 006 helper contract with a delete/backspace op; deletes ride the control-key `KeyEvent` lane, which is live-observed working for control keys on macOS Screen Sharing. Additionally, like Chrome Remote Desktop, dedicated Backspace (⌫) and Enter (↵) buttons stay visible on the Live input surface — the existing Compose action row already renders ⌫/↵ via `ComposeQuickKey`, and Live mode reuses it.
2. **Given** an open Live editing window, **When** the user presses Return/Enter (via the soft keyboard or the reused ↵ action button), **Then** Naru flushes any coalesced pending inserts, delivers the line boundary as a remote `Return` key event on the VNC key lane, seals the window, and opens a fresh window for the next line.
3. **Given** rapid typing, **When** several units commit within a short dispatch window, **Then** consecutive inserts MAY coalesce into a single delivery, but a delete always flushes pending inserts first so remote ordering is preserved.

---

### User Story 4 — Honest Fallback When The Helper Is Absent (Priority: P2)

A user without a paired helper switches to Live mode. Naru either delivers through a clearly-disclosed degraded transport or tells the truth about what live typing can and cannot do on this session, and never silently drops the user's characters.

**Why this priority**: The helper is optional (constitution §V, spec 006). Live mode must degrade honestly: the chunked-clipboard fallback carries a ~0.30 s settle per chunk and overwrites the remote general clipboard (disclosed, unconfirmed — not helper-grade live), and the ASCII-only key-event path cannot carry Korean/CJK/emoji to macOS. Overclaiming "live" on a path that cannot confirm delivery repeats the exact failure mode this feature exists to fix. Per founder decision D2 (2026-07-05), Naru still offers Live without a helper through the disclosed chunked-clipboard tier rather than refusing Live entirely.

**Independent Test**: With no helper paired and a fake RFB server, switch to Live mode and type ASCII plus a Korean unit. With clipboard usable, assert both the ASCII commit and the Korean unit deliver via the disclosed chunked-clipboard tier (UTF-8 clipboard carries Korean; the status line discloses the degraded/unconfirmed/settle-latency transport and clipboard overwrite) — never as Unicode `KeyEvent` garbage. Then with clipboard unavailable/blocked, assert the Korean unit is retained locally with a safe failure that names the missing confirmed transport and is never silently dropped.

**Acceptance Scenarios**:

1. **Given** no paired helper and a session where VNC clipboard paste is usable, **When** the user live-types, **Then** Naru delivers via chunked clipboard paste and MUST disclose that this transport is unconfirmed and carries settle latency (not real-time), so the experience is not misrepresented as helper-grade live. **Resolved 2026-07-05 (founder decision D2)**: Live mode IS offered without a helper via chunked clipboard+paste — per-commit chunks, or short-window coalesced chunks — rather than forcing a fall back to Compose & Send. The degraded nature (the remote general clipboard is overwritten, and each chunk carries ~0.3 s settle) MUST be disclosed in the UI status line. Helper `nativeInsert` stays the primary adapter whenever the helper is reachable; the clipboard chunk tier is the disclosed degraded path only when no helper is available.
2. **Given** no paired helper and a Korean/CJK/emoji unit that only the clipboard or key-event path could carry, **When** the clipboard path is unavailable or blocked, **Then** Naru retains the user's text locally and shows a safe failure that names the missing confirmed transport; it never emits Unicode `KeyEvent`s to a macOS target.
3. **Given** an ASCII-only commit with no helper and no usable clipboard, **When** the last-resort path is used, **Then** Naru MAY deliver via ASCII VNC `KeyEvent` and MUST disclose that this last-resort path is ASCII-only (non-multilingual).

---

### User Story 5 — Desync Safety: Focus Loss And Remote Cursor Moves (Priority: P2)

The user live-types, then taps the trackpad to move the remote cursor, or the remote app loses focus, or the connection blips. In every case Naru must not blindly keep editing a stale window and must not issue destructive deletes into content it can no longer account for.

**Why this priority**: Naru cannot read the remote insertion point back over VNC. The mirror is only valid while nothing moves the remote cursor out from under it. A retroactive delete issued after the cursor moved could destroy unrelated remote content — a data-loss hazard that must be designed out, not patched later.

**Independent Test**: With a fake helper recorder, open a Live window and deliver some text, then simulate (a) a pointer/trackpad event, (b) a helper focus-unavailable signal, and (c) a session interruption. Assert each event seals the window and that no delete op is emitted across the seal on any subsequent backspace.

**Acceptance Scenarios**:

1. **Given** an open Live editing window, **When** the user performs any pointer/trackpad interaction that could move the remote insertion point, **Then** Naru seals the current window (committed text stays; no retroactive delete may cross the seal) and opens a fresh window for subsequent typing.
2. **Given** an open Live editing window, **When** the helper reports a focus change / focus-unavailable state (spec 006 `helper.focusUnavailable`), or the session leaves `.active`, or the app backgrounds, **Then** Naru seals the window, retains any not-yet-delivered local text, and surfaces the state as a fixed safe label without leaking typed content.
3. **Given** a sealed window, **When** the user resumes typing, **Then** a new window opens and only forward inserts occur until a new correction happens inside the new window — deletes never reach back past a seal.

### Edge Cases

- The focused remote app is a secure-input field or blocks paste/text events; Naru cannot detect this over VNC (same boundary as spec 002 / spec 006). Live mode discloses the transport but cannot guarantee arrival on the clipboard/key-event fallbacks.
- IME candidate re-selection changes already-committed characters (e.g., Japanese conversion, Korean auto-spacing) — treated as a correction inside the current window, subject to US3 correction semantics.
- Dictation inserts a large committed block at once — delivered as one (possibly coalesced) insert, not per character.
- The user pastes text from the iOS pasteboard into the Live field — delivered as a single committed insert unit.
- Network changes mid-window (Wi-Fi ↔ cellular): helper reachability may differ from VNC reachability; a reachability loss seals the window and retains undelivered text.
- Helper accepts a request but the insert fails after acceptance (spec 006 `helper.permissionMissing` / `helper.focusUnavailable`) — window seals, safe failure code only, local text retained.
- Extremely fast typing exceeds the per-window dispatch rate limit — coalescing and rate limiting absorb it without reordering or dropping committed content.
- Emoji / combining characters / grapheme clusters must be delivered as whole grapheme units, never split mid-cluster.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST present Live type-through as a distinct Remote Input Dock mode, switchable in one tap among Compose & Send (default), Live type-through, and Direct Keystroke (spec 002). The active mode MUST be visibly indicated.
- **FR-002**: In Live mode, only committed (unmarked) IME text MUST cross the boundary; text still in the marked/composing state MUST NOT be sent. There MUST be no Send button in Live mode — commit is the trigger.
- **FR-003**: System MUST define the commit unit as the delta between the text already reflected to the remote for the current editing window and the current committed text, delivered as insert operations at each IME composition-commit boundary and at grapheme-cluster boundaries (never splitting a grapheme).
- **FR-004**: System MUST use the injection adapter ladder in this precedence: (1) helper text bridge `nativeInsert` (primary; the only path with observed delivery confirmation), (2) chunked VNC clipboard paste (fallback; unconfirmed; settle latency disclosed), (3) ASCII-only VNC `KeyEvent` (last resort; non-multilingual). Naming and precedence MUST be explicit per constitution §I.
- **FR-005**: System MUST NOT emit Unicode X11 keysyms via `KeyEvent` to a macOS target (live-observed `no-input`, 2026-07-05). The `KeyEvent` path is restricted to ASCII commit units (last-resort insert tier) and to control keys — `BackSpace` (deletes, D1) and `Return`/`Enter` (line boundaries) — which are the live-observed working key lane on macOS Screen Sharing.
- **FR-006**: System MUST choose one **insert** adapter per editing window at window open based on current capability and MUST NOT switch insert adapters mid-window; an insert-adapter failure MUST seal the window, retain undelivered text, and surface a safe failure rather than silently retrying on a different insert tier. The control-key `KeyEvent` lane used for `BackSpace` deletes (D1) and `Return` line boundaries is orthogonal to the insert-adapter choice and is not an adapter switch; it is always the VNC key lane regardless of which insert tier the window selected.
- **FR-007**: System MUST preserve strict per-window operation ordering (FIFO). A delete operation MUST flush any pending coalesced inserts before it is applied so the remote never observes reordered content.
- **FR-008**: System MUST coalesce consecutive inserts within a short dispatch window into fewer operations and MUST rate-limit deliveries to protect the helper and remote from per-keystroke request floods, without dropping or reordering committed content.
- **FR-009**: System MUST reconcile in-window corrections (backspace, IME re-selection) by emitting the minimal insert/delete operations needed to match the local editing window, subject to the retroactive-delete boundary in FR-011. Per founder decision D1 (2026-07-05), a delete MAY reach text already delivered to the remote **within the current unsealed window**; it is delivered as one remote `BackSpace` key event (X11 keysym `0xff08`) per grapheme through the existing VNC `KeyEvent` lane, not through a new helper delete op. Deletes MUST NOT cross a seal (FR-011).
- **FR-010**: System MUST deliver a line boundary (Return/Enter) by flushing pending inserts, delivering the boundary as a remote `Return` key event (X11 keysym `0xff0d`) through the VNC `KeyEvent` control-key lane (per FR-005, not the insert adapter), sealing the window, and opening a fresh window.
- **FR-011**: System MUST seal the current editing window — after which no delete operation may cross the seal into previously delivered text — on any of: pointer/trackpad interaction that could move the remote cursor, helper focus-change / focus-unavailable signal, session leaving `.active`, app backgrounding, local keyboard focus loss, mode switch, disconnect/reconnect, or profile change.
- **FR-012**: System MUST NOT lose user work on a switch: switching to Compose restores its retained draft; switching into Live opens a fresh window; the Live field holds no batch "draft" — sealing leaves delivered text at the remote and discards only marked/uncommitted text.
- **FR-013**: System MUST surface per-window delivery status using fixed catalog values (e.g., delivering / delivered-observed for the helper path / unconfirmed for the clipboard path) and MUST NOT present the helper path's observed delivery as an "unknown" result.
- **FR-014**: System MUST disclose a degraded transport: the clipboard fallback MUST disclose it is unconfirmed with settle latency (not real-time), and the ASCII last-resort MUST disclose it is ASCII-only.
- **FR-015**: System MUST retain the user's not-yet-delivered local text on any delivery failure so the user can retry, switch modes, or seal, and MUST NOT silently drop committed characters.
- **FR-016**: System MUST reset the active dock mode to Compose & Send on every fresh session start (constitution §I default). Live mode MUST NOT persist across disconnect/reconnect or app relaunch. **Resolved 2026-07-05 (founder decision D3)**: Live type-through ships as a user-selectable mode alongside Compose & Send and Direct Keystroke; the default remains Compose & Send. Once physical-device verification (the residual iPhone+Mac gates) passes, Live type-through is intended to become the default multilingual input path, but that promotion — and the accompanying constitution §I amendment — happens at promotion time, not in this change. This spec ships Live as explicit opt-in only.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: iPhone/iPad native-keyboard text including Korean/CJK/emoji and dictated text. IME composition (Hangul assembly, kana conversion, candidate selection) happens locally; only committed units cross. This keeps Live mode within constitution §I — it is *not* per-keystroke Unicode streaming; marked text never leaves the device.
- **IN-002**: Remote injection behavior: committed units are injected at the remote insertion point as they commit, primarily via helper `nativeInsert`, with in-window corrections reconciled as minimal insert/delete ops. No Send action; commit is the trigger.
- **IN-003**: Fallback behavior: helper absent/unreachable → chunked clipboard paste (disclosed, unconfirmed, settle latency); Korean/CJK/emoji with no confirmed transport → retained locally with safe failure; ASCII-only remainder → optional ASCII `KeyEvent` last resort. Unicode `KeyEvent` to macOS is forbidden.
- **IN-004**: Clipboard impact: the primary helper path SHOULD NOT change the user's Mac general pasteboard (spec 006 IN-004). The clipboard fallback tier necessarily uses the pasteboard and MUST restore or clearly report restore failure; the user MUST be told the clipboard path is in use.
- **IN-005**: User confirmation: no per-unit confirmation (commit is the send); confirmation lives at mode entry (mode is an explicit opt-in with a persistent transport/latency disclosure badge). No background replay or buffered delivery after disconnect.

### Tailnet / Connection Requirements *(mandatory if feature touches connection)*

- **TN-001**: Private-network assumption: Live mode rides the existing VNC session and the spec 006 helper pairing, both scoped to saved private profiles and MagicDNS/manual private hosts.
- **TN-002**: Diagnostics shown to user: active adapter tier, helper pairing/reachability/permission state, per-window delivery status (fixed labels), and last safe failure code — no typed content.
- **TN-003**: Public internet posture: inherited from spec 006 — helper control endpoints MUST NOT encourage public exposure; no new public posture.

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing the local/remote boundary: streamed committed text deltas, delete/backspace operation counts, line boundaries, the profile helper pairing identifier, and fixed request/result IDs. This is a higher-frequency stream than spec 006's single final payload; the same redaction rules apply per operation.
- **SP-002**: Data retained on device: dock mode selection, helper pairing metadata and enabled/disabled state, last fixed delivery/failure code, and the in-memory current editing-window mirror only. Typed content, deltas, and backspace counts MUST NOT be persisted beyond the live in-memory window.
- **SP-003**: Data retained on helper/remote host: helper pairing metadata and fixed recent status only. Raw inserted/deleted text MUST NOT be logged or persisted by the helper by default (spec 006 SP-003).
- **SP-004**: Sensitive actions needing approval: entering Live mode (explicit opt-in), helper pairing/enable/disable/revocation (spec 006). Individual commit deliveries are not separately approval-gated (commit is the trigger); the persistent transport disclosure badge is the standing notice.
- **SP-005**: Logging rule: logs, diagnostics, and telemetry MUST NOT include typed content, committed deltas, marked text, per-unit backspace/delete counts that could reconstruct content, clipboard contents, host name, helper endpoint, tokens, passwords, framebuffer pixels, coordinates, raw key events, or exact per-unit timing samples. Only fixed catalog states and bucketed aggregates may be recorded.

### Key Entities *(include if feature involves data)*

- **LiveTypeThroughMode** — dock state on the app model controlling whether Live mode is active, the currently selected adapter tier for the open window, and the persistent disclosure. Peer to `DirectKeystrokeMode` (spec 002). Resets to Compose default on session start.
- **LiveEditingWindow** — the in-memory mirror of what Naru believes it has delivered to the remote insertion point since the window opened. Key attributes: delivered-text mirror (process-local), pending coalesced insert buffer, sealed flag, invalidation reason (fixed catalog), and active adapter tier. Bounded to the current line/window; sealed and discarded on the FR-011 events.
- **LiveInsertOperation / LiveDeleteOperation** — one forward insert (committed delta) or one bounded delete-back reconciliation, carrying encoding class, approximate size bucket, adapter tier, ordering index, and fixed result code. Raw text is process-local only. Per D1, a `LiveDeleteOperation` carries a grapheme count and is realized as that many remote `BackSpace` `KeyEvent`s on the VNC key lane (no spec 006 helper contract extension in v1).
- **LiveDeliveryStatus** — per-window fixed-catalog status (e.g., `delivering`, `deliveredObserved`, `unconfirmedClipboard`, `asciiLastResort`, `retainedFailure`) surfaced in the dock and diagnostics.

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI, every user-facing scenario lists an iPhone path (physical first for delivery/latency claims) before any iPad path; iPad-only affordances are graceful-scaling rows, not primary.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Marked text is not sent; committed Korean unit delivered via helper `nativeInsert`; no VNC clipboard/paste/Unicode KeyEvent | XCTest + fake helper | iPhone (simulator) | `swift test` app-model/text-injection test capturing per-commit helper requests and absence of VNC writes |
| Adapter ladder precedence + failure sealing (helper → clipboard chunked → ASCII KeyEvent; failure retains text) | XCTest + Fake RFB / fake helper | iPhone (simulator) | `swift test` asserting tier selection, single-adapter-per-window, safe failure on tier failure |
| In-window correction reconciles with minimal ordered insert/delete; Return flushes+seals | Unit + fake helper recorder | iPhone (simulator) | `swift test` asserting op sequence for `hte`→backspace→`e`→Return |
| Window seals on pointer/trackpad, focus-unavailable, disconnect; no delete crosses seal | XCTest | iPhone (simulator) | `swift test` asserting seal + no cross-seal delete on subsequent backspace |
| Three-mode one-tap switch preserves Compose draft, clears Direct modifiers, seals Live window | Unit (model) | iPhone (simulator) | `swift test` for Remote Input Dock model transitions |
| Korean/mixed 200-char integrity (no loss/dup/reorder/mid-composition send), 10 iterations | Live probe + manual | iPhone (physical) | `helper-text-observed-probe` (unicode-hangul) + PRODUCT_QUALITY_TARGETS.md §6.1 integrity gate log |
| Per-commit delivery latency (commit → helper request / observed insert) | Live latency probe | iPhone (physical) | New per-commit latency probe extending `helper-text-observed-probe`; p95 recorded |
| Unicode `KeyEvent` to macOS remains `no-input` (regression guard) | Live probe | iPhone (physical) + Mac | `text-keystroke-observed-probe` (unicode-hangul) recorded `no-input` |
| 30-minute sustained live-typing session (no loss, no desync, no runaway heat) | Manual device | iPhone (physical) | Manual session log + diagnostic export |
| Diagnostics carry only fixed labels; no typed content/deltas/timings | Unit (privacy) | iPhone (simulator) / N/A | Diagnostic export privacy assertion |
| iPad graceful scaling: Live mode dock + disclosure render and behave the same | Screenshot/XCUITest | iPad-graceful | Screenshot artifact after the iPhone paths pass |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a paired-helper session, a committed Korean/CJK/emoji unit is delivered to the remote insertion point with a fixed observed-delivery status (not "unknown"), with no separate Send action, and with marked/in-composition text never crossing the boundary.
- **SC-002**: Per-commit delivery latency (commit boundary → helper `nativeInsert` request accepted / observed insert) is materially lower than the batch Compose per-sentence budget of ~1–1.3 s (`docs/PERFORMANCE_PARITY_ANALYSIS.md` §4.3); target a helper-path p95 in the few-hundred-ms class on a local private network, excluding permission prompts. [exact numeric gate set in plan/quality targets]
- **SC-003**: A 200-character Korean/English/number/symbol mixed sentence typed live, over 10 iterations, arrives with no loss, duplication, reordering, or mid-composition (partial-syllable) characters (PRODUCT_QUALITY_TARGETS.md §6.1).
- **SC-004**: No window desync ever causes a delete to be applied to remote content outside the current editing window; pointer/focus/disconnect events provably seal the window.
- **SC-005**: With no helper, Live mode never delivers Korean/CJK/emoji as garbage keysyms and never silently drops committed characters — it either delivers via a disclosed transport or retains the text with a safe failure.
- **SC-006**: No typed content, committed delta, marked text, or per-unit timing appears in any diagnostic export, log, or telemetry — verified by a privacy test.
- **SC-007**: A 30-minute sustained live-typing iPhone session shows no accumulated desync, input loss, unrecoverable state, or sustained serious thermal (PRODUCT_QUALITY_TARGETS.md §2.1, §10).

## Assumptions

- The first (and confirmed) primary transport is the spec 006 helper on macOS, because that is the only path that delivered Hangul with observed confirmation (2026-07-05). Live mode augments input; it does not replace RFB viewing or the batch Compose path.
- Physical iPhone + Mac evidence is required before promoting any Live-mode default; simulator + fake-helper + live-probe tests are necessary but not sufficient (constitution §III/§VI).
- The iOS native keyboard exposes committed vs marked text boundaries reliably enough to gate on commit (the existing marked-text protection in Compose is evidence this is tractable; `docs/PERFORMANCE_PARITY_ANALYSIS.md` §4.3).
- Naru cannot read the remote insertion point back over VNC; the editing-window mirror is only valid until something moves the remote cursor, which is why FR-011 seals aggressively.
- Constitution §I is satisfied because composition stays local and only committed units cross — Live mode is a commit-granularity change to the local-composition model, not raw Unicode key streaming.

## Non-Goals

- **Voice/dictation streaming as its own pipeline** — dictation is accepted as committed text through the same path, but a dedicated voice feature is out of scope.
- **Image/file paste, staging, or agent handoff** — out of scope; separate features.
- **Non-macOS hosts** — the confirmed transport and forbidden-transport evidence are macOS Screen Sharing specific. Behavior on Linux/Windows VNC (which may accept Unicode keysyms, or whose helpers do not exist) is a residual: the adapter ladder MUST NOT assume macOS everywhere, but this spec does not define/verify non-mac tiers. [residual risk — a later spec covers non-mac host tiers]
- **Bidirectional sync / reading remote text back** — Live mode is write-forward with a local mirror; it does not observe remote content.
- **Retroactive editing across a sealed window** — once a window seals, delivered text is immutable from Live mode's perspective (data-loss safety).
- **Replacing Compose & Send or Direct Keystroke** — all three modes coexist; Compose remains the reviewed multilingual default per constitution §I (Live promotion to default is deferred to a later change per D3), Direct remains the raw terminal-key path.
- **Making Live mode work without any confirmed or disclosed transport** — if neither helper nor a disclosed fallback can carry the content, Live mode fails honestly rather than pretending.
