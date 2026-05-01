# Feature Specification: Direct Keystroke Streaming Mode

**Feature Branch**: `002-direct-keystroke-mode`
**Created**: 2026-05-02
**Status**: Draft
**Product**: Naru Remote
**Input**: Founder workflow signal — sustained AI-coding from iPhone over VNC requires terminal-grade per-keystroke input (Tab, Esc, Ctrl combos, arrows). PRODUCT_SPEC.md §6.3.6 names the mode; this feature spec replaces the §6.3.6 assumption that iOS's system keyboard would be reused. Founder explicitly chose Chrome Remote Desktop Android's pattern: a custom in-app soft keyboard with two pages (QWERTY + special keys), bottom-docked, with sticky modifiers — the iOS system keyboard's IME composition, autocorrect, predictive text, and missing terminal keys make it unsuitable as a raw-keystroke source.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Drive A Remote Shell From iPhone (Priority: P1)

The founder is mid-flight or away from a desk and needs to keep working on a long-running terminal session — Ghostty/Codex/tmux — that lives on a Mac on Tailnet. They tap into Naru Remote, switch the Remote Input Dock to Direct Keystroke mode, and type into the remote shell with each on-screen tap producing exactly one keystroke at the remote: letters, space, return, backspace, plus terminal-essential keys (Tab for completion, Ctrl-C to cancel, arrows for shell history, Esc for vim).

**Why this priority**: Without per-keystroke streaming, the existing Compose & Send flow cannot drive a shell — `Tab`, `Ctrl-C`, arrow-key history navigation, `Esc` for vim, and any TUI app are unreachable. The founder's own ICP (sustained AI-coding from phone, see `feedback_phase9_keyboard_is_ship_blocker`) hinges on this story. The MVP cannot be considered ship-ready while a terminal session from iPhone is impossible.

**Independent Test**: With a fake RFB server recording client messages, switch the dock to Direct Keystroke mode, tap `q`, `w`, `e`, `Tab`, `Ctrl`+`c`, `Esc`, `Up arrow` on the custom keyboard, and verify the server received seven `KeyEvent` (msg type 4) pairs (down then up) with the correct X11 keysyms and the correct down/up timing for the Ctrl-C combo (Ctrl down → c down → c up → Ctrl up).

**Acceptance Scenarios**:

1. **Given** the user is in an active VNC session with a focused remote terminal, **When** they tap the Direct Keystroke toggle on the Remote Input Dock, **Then** the iOS system keyboard is dismissed (if visible), the custom soft keyboard appears bottom-docked showing the QWERTY page, the dock shows a persistent "Direct mode" badge, and a one-time per-session warning explains "IME / autocorrect / dictation are bypassed in this mode."
2. **Given** the custom keyboard is showing the QWERTY page, **When** the user taps a letter key, **Then** Naru sends a `KeyEvent` down message followed immediately by a `KeyEvent` up message for that letter's X11 keysym, and no local clipboard, compose buffer, or text accumulator is touched.
3. **Given** the user taps the special-keys page toggle, **When** the page swaps, **Then** the QWERTY page is hidden and a special-keys page replaces it in the same dock area showing Tab, Esc, Ctrl, Alt, Cmd, Shift, Up/Down/Left/Right, F1–F12, Home, End, PgUp, PgDn, Insert, Delete; an inverse toggle returns to QWERTY without sending any keystroke.

---

### User Story 2 — Send Modifier Combinations The Way A Real Keyboard Does (Priority: P1)

The user needs Ctrl-C, Ctrl-R, Cmd-Tab, Shift-Arrow selection, Alt-key combos. On a one-finger touchscreen they can't physically hold a modifier and press a letter at the same time, so they need a *sticky modifier* affordance — tap a modifier once to arm it for the next non-modifier key only, double-tap to lock it until released.

**Why this priority**: Without modifier combos, Direct mode is barely better than nothing for a terminal — `Ctrl`, `Alt`, `Cmd`, and `Shift` cover most shell shortcuts. Modeled after Chrome Remote Desktop Android.

**Independent Test**: With a fake RFB server, on the special-keys page tap `Ctrl` (badge highlights "armed"), tap `c` — assert the wire saw `Ctrl down → c down → c up → Ctrl up` and the modifier badge returned to idle. Then double-tap `Shift` (badge highlights "locked"), tap `a`, `b`, `c` — assert each letter went out with `Shift` held throughout, then tap `Shift` again to release, tap `d` — assert `d` went out with no `Shift`.

**Acceptance Scenarios**:

1. **Given** the modifier `Ctrl` is in idle state, **When** the user taps `Ctrl` once, **Then** the on-screen `Ctrl` key visibly highlights as "armed", but no `KeyEvent` is sent yet.
2. **Given** `Ctrl` is armed, **When** the user taps `c`, **Then** Naru sends `Ctrl down → c down → c up → Ctrl up`, and the on-screen `Ctrl` returns to idle highlighting.
3. **Given** `Ctrl` is armed, **When** the user taps another modifier (`Shift`), **Then** both modifiers stack into armed state and apply to the next non-modifier key (e.g., `Ctrl-Shift-Tab` is reachable).
4. **Given** `Shift` is in idle state, **When** the user double-taps `Shift` within 400 ms, **Then** the `Shift` key locks (visibly distinct from "armed"), and every subsequent non-modifier keystroke is sent with `Shift` held until the user taps `Shift` again.
5. **Given** `Shift` is locked, **When** the user taps `Shift` once, **Then** `Shift` releases and returns to idle.

---

### User Story 3 — Use A Bluetooth / Magic Keyboard When Available (Priority: P2)

When the user attaches a Bluetooth or Magic Keyboard to the iPhone or iPad while Direct mode is active, hardware keystrokes are forwarded directly to the remote without going through the on-screen keyboard. This matches the desk-and-keyboard "real workstation" scenario where the on-screen keyboard is in the way.

**Why this priority**: Hardware keyboards remove the touchscreen modifier limitation entirely (Ctrl-Shift-Tab is one chord, not three taps) and unlock realistic typing speed. Important enough to ship together with the on-screen path because both code paths share the keysym mapping table — splitting them later means rewriting the table.

**Independent Test**: With an iPad simulator and a software-attached hardware keyboard, switch to Direct mode and type a sequence including Tab, Esc, Cmd-Tab, arrow keys; assert the fake RFB server received the same `KeyEvent` byte sequence as the on-screen path produces for the same logical keys.

**Acceptance Scenarios**:

1. **Given** Direct mode is active and a Bluetooth keyboard is connected, **When** the user presses a hardware key, **Then** Naru sends a `KeyEvent` down on press and a `KeyEvent` up on release, identical to the on-screen path's emission for the same key.
2. **Given** Direct mode is active with a hardware keyboard connected, **When** the user holds a hardware key, **Then** the iOS press cycle's auto-repeat is honored — Naru emits one `KeyEvent` down on the initial press and one `KeyEvent` up on release; no per-repeat extra `KeyEvent` is synthesized by Naru (the remote OS owns auto-repeat once `down` is held).
3. **Given** Direct mode is active and a hardware keyboard is connected, **When** the user uses the on-screen Direct keyboard at the same time (e.g., one-handed scenario), **Then** both input sources coexist without the modifier sticky-state of one source corrupting the other.
4. **Given** Direct mode is *off* (Compose mode), **When** a hardware key is pressed, **Then** Naru does **not** stream raw keystrokes to the remote — Compose & Send remains the path (constitution §I default).

---

### User Story 4 — Switch Between Compose And Direct Without Losing State (Priority: P2)

The user is alternating between writing a Korean message in Compose mode and running a quick `git status` in Direct mode. Mode switching must be unambiguous (different keyboards = different modes) and should not silently lose either side's working state.

**Why this priority**: Mixing-mode use is the realistic phone workflow — type a sentence in Compose, send, drop into Direct for shell, back to Compose. Constitution §I requires Compose & Send to be the default; this story keeps the toggle reversible and obvious.

**Independent Test**: From an active session with a partial Compose draft, toggle Direct mode → assert Compose draft is preserved (not sent, not dropped, still visible when toggling back) and the on-screen keyboard visibly changes to the custom Direct keyboard. Toggle back → assert the iOS system keyboard reappears and the partial draft is still there.

**Acceptance Scenarios**:

1. **Given** a partial Compose draft exists, **When** the user toggles into Direct mode, **Then** the draft is retained in `RemoteInputDock` state but hidden from view, and toggling back to Compose restores the draft exactly as it was.
2. **Given** Direct mode is active with one or more modifiers locked, **When** the user toggles back to Compose, **Then** all sticky modifier state is cleared and Compose mode opens with no latent modifier influence on a future Direct session.
3. **Given** the user is in Direct mode, **When** they connect/disconnect or change profile, **Then** the mode resets to Compose (constitution §I default) on the next session start.

---

### User Story 5 — Sticky Modifier UX Refinements (Priority: P3)

Visual feedback for armed vs locked modifiers, double-tap window tuning, and recovery affordance ("Clear modifiers" button) are polish items that round out the Chrome Remote pattern.

**Why this priority**: The functional behavior is in P1; this story is about visual clarity and one explicit "panic clear" affordance for when sticky state gets confusing.

**Independent Test**: Visual inspection on iPhone simulator — armed-state and locked-state highlighting are visually distinct from idle and from each other; "Clear modifiers" button on the special-keys page is reachable in one tap.

**Acceptance Scenarios**:

1. **Given** any modifier is armed or locked, **When** the user taps a "Clear modifiers" affordance on the special-keys page, **Then** all sticky modifier state returns to idle and no `KeyEvent` is emitted.
2. **Given** a modifier is armed (single-tap), **When** the user taps it a second time within 400 ms, **Then** it transitions to locked; tapping outside the window starts a fresh single-tap arm cycle on the second tap.

### Edge Cases

- **Remote secure-input field** (e.g., macOS "Secure keyboard entry" or password prompt): Naru cannot detect remote secure-input state. Direct mode keystrokes are sent regardless — same boundary as Compose & Send. The persistent "Direct mode" badge is the user-visible warning.
- **Remote app loses focus mid-session**: per-key `KeyEvent`s are still sent; whether they reach a focused control is the remote's responsibility. Naru does not buffer.
- **VNC clipboard messages mid-keystroke**: incoming `ServerCutText` is independent of `KeyEvent` send direction; the existing `RemoteClipboardTextClient` boundary is untouched.
- **Hardware key with no X11 keysym** (e.g., Globe / Dictation): Naru drops the event silently and surfaces no error — emitting "unknown" placeholder keysyms could corrupt remote state.
- **Mode toggle during reconnect**: existing `ReconnectPolicy` window owns reconnect; mode toggle is allowed but no `KeyEvent` is sent until the session returns to `.active`.
- **iPad-only — Stage Manager / multi-window**: the bottom-docked Direct keyboard is per-window; modifier state lives in `RemoteInputDock` and resets per-window per constitution §VI (graceful scaling, not a primary scenario).
- **Localization**: QWERTY page is English-only; Korean / CJK / emoji input is explicitly **not** supported in Direct mode (Compose & Send is the IME path; constitution §I).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST present a custom in-app soft keyboard when Direct Keystroke mode is active. The iOS system keyboard MUST be dismissed during Direct mode and MUST NOT contribute keystrokes to the wire.
- **FR-002**: System MUST provide two pages — a QWERTY page and a special-keys page — togglable from the keyboard view itself, and the page toggle MUST NOT emit any `KeyEvent`.
- **FR-003**: User MUST be able to toggle between Compose & Send (default) and Direct Keystroke mode from the Remote Input Dock in one tap.
- **FR-004**: System MUST emit one RFB `KeyEvent` (RFC 6143 §7.5.4, message type 4, 8 bytes) on key down and one on key up for every on-screen tap, with the X11 keysym corresponding to the key plus current sticky-modifier state.
- **FR-005**: System MUST implement sticky modifiers — Ctrl / Shift / Alt / Cmd. Tap once = armed for the next single non-modifier key (auto-released after); double-tap within 400 ms = locked until tapped again. Locked and armed states MUST be visually distinct from idle.
- **FR-006**: System MUST forward Bluetooth / Magic Keyboard hardware keystrokes through the same X11 keysym mapping as the on-screen keyboard when Direct mode is active. Hardware presses produce one `KeyEvent` down on press and one up on release; no auto-repeat synthesis from Naru.
- **FR-007**: System MUST NOT stream hardware keystrokes when Direct mode is *off* — Compose & Send remains the path (constitution §I default).
- **FR-008**: System MUST NOT touch the local or remote clipboard during Direct mode keystroke emission. The clipboard remains owned by Compose & Send and `RemoteClipboardTextClient`.
- **FR-009**: System MUST show a one-time-per-session warning the first time the user enters Direct mode informing them that IME composition, autocorrect, predictive text, and dictation are bypassed.
- **FR-010**: System MUST show a persistent "Direct mode" indicator on the Remote Input Dock while the mode is active, and the same indicator MUST surface on a session-level HUD so the mode is visible even when the keyboard is collapsed.
- **FR-011**: System MUST preserve a partial Compose draft when the user toggles into Direct mode, and restore it when toggling back to Compose. Toggling MUST NOT send the draft.
- **FR-012**: System MUST clear all sticky modifier state when the user toggles out of Direct mode, when the session ends, when the active profile changes, and on `connect` start. A new Direct mode session begins with all modifiers idle.
- **FR-013**: User MUST be able to clear all sticky modifier state in one tap via a "Clear modifiers" affordance on the special-keys page.
- **FR-014**: System MUST reset the mode to Compose & Send on every fresh session start (per profile connect). Direct mode MUST NOT persist across disconnect / reconnect cycles or app launches.
- **FR-015**: System MUST drop hardware keystrokes that have no X11 keysym mapping silently, without emitting a `KeyEvent` and without surfacing an error.

[NEEDS CLARIFICATION: should soft-key press-and-hold trigger key-repeat (continuous `KeyEvent` down at ~30 Hz until release, with a single `KeyEvent` up on release) or one-shot only — Chrome Remote Android does soft-key auto-repeat; one-shot is simpler and matches hardware-keyboard behavior in FR-006]

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001 Local composition path**: **none** — Direct mode is the explicit constitution §I "MAY" exception (remote key events as the *primary* path is allowed because the user has opted in by toggling the mode). No compose buffer, no autocorrect, no predictive text. Local IME is bypassed by *not* using a `UITextInput`-conforming view.
- **IN-002 Remote injection behavior**: per-key RFB `KeyEvent` (down / up pairs), 8 bytes per RFC 6143 §7.5.4, big-endian keysym, sent immediately on tap or hardware press / release. No batching, no debouncing.
- **IN-003 Fallback behavior**: when the remote application rejects, drops focus, or the connection lapses (existing `RemoteSessionState` not `.active`), `KeyEvent`s are dropped silently. Direct mode does **not** keep a buffer; this is intentional — Compose & Send is the buffered path.
- **IN-004 Clipboard impact**: **none**. Direct mode does not read or write local or remote clipboards.
- **IN-005 User confirmation**: **none on send** — the tap *is* the send. Confirmation lives at mode entry: a one-time warning on first activation per session and a persistent on-screen "Direct mode" badge while active.

### Tailnet / Connection Requirements *(mandatory if feature touches connection)*

- **TN-001 Private-network assumption**: inherited from MVP — Direct mode rides on the existing VNC session; no new connection assumptions.
- **TN-002 Diagnostics shown to user**: `KeyEvent` write failures (e.g., RFB write throws) surface through the existing safe-catalog diagnostic path; Naru MUST NOT include keystroke content in any diagnostic export (constitution §IV).
- **TN-003 Public internet posture**: inherited from MVP — N/A new posture.

### Security & Privacy Requirements *(mandatory)*

- **SP-001 Data crossing local→remote**: per-key X11 keysyms (8 bytes per `KeyEvent`). Modifier state is reflected by adjacent down/up events for modifier keysyms — no separate "modifier mask" leaks.
- **SP-002 Data retained on device**: **none related to keystrokes**. No local buffer, no history, no logging. Mode-toggle state and current sticky-modifier state are in-memory and cleared on disconnect / profile change / app exit.
- **SP-003 Data retained on helper / remote host**: Naru cannot control remote-side shell history, key loggers, or crash dumps — that is the remote OS's policy. The user opted into Direct mode; the persistent on-screen badge is the disclosure.
- **SP-004 Sensitive actions needing approval**: mode entry shows a one-time-per-session warning and the persistent badge. Naru does **not** detect remote secure-input fields (same boundary as Compose & Send); the user is responsible for the remote target.
- **SP-005 Logging rule**: keystroke content (key codes, keysyms, scancode) MUST NOT be written to any log, diagnostic, telemetry, or crash report. Mode-toggle events and modifier-state-change events MAY be logged but **without** the active modifier set or the most-recent key. Diagnostic export's safe-catalog stays unchanged (caller-provided strings are still rejected per existing `DiagnosticExport` rule).

### Key Entities *(include if feature involves data)*

- **DirectKeystrokeMode** — boolean state on `NaruRemoteAppModel` (or sub-model in `RemoteInputDock`) controlling the active input mode. Default `false`. Resets to `false` on every session start.
- **StickyModifierState** — small struct tracking the current state of each modifier (Ctrl / Shift / Alt / Cmd) as one of `idle | armed | locked`. Single-source-of-truth for both the on-screen keyboard's visual state and the keysym emission path.
- **KeyboardPage** — enum `qwerty | special` controlling which set of keys the custom keyboard renders. Defaults to `qwerty` on every Direct-mode entry.
- **KeysymMapping** — table mapping each on-screen key (and each `UIKey.keyCode` from hardware) to an X11 keysym. Shared by on-screen and hardware paths to prevent divergence.
- **KeystrokeEmitter** — boundary that turns one logical key event (key, down/up, current modifier set) into one RFB `KeyEvent` on the wire. Capability protocol on the existing RFB boundary (peer to `RemoteClipboardTextClient`, `RFBPointerEventClient`).

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI, every user-facing scenario lists an iPhone path before any iPad path; iPad-only affordances are graceful scaling rows, not primary.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Single QWERTY tap → 1 down + 1 up `KeyEvent` on wire | Unit + Fake RFB | iPhone (simulator) | `swift test` passes; `FakeRFBClientMessageRecorder` captures the byte sequence |
| Special-keys page emits Tab / Esc / arrows / F1–F12 with correct keysyms | Unit | iPhone (simulator) | `swift test` keysym table coverage 100 % |
| Sticky modifier `Ctrl` armed → tap `c` → `Ctrl down, c down, c up, Ctrl up` | Unit + Fake RFB | iPhone (simulator) | `swift test` asserts byte sequence and modifier auto-release |
| Sticky modifier `Shift` double-tap within 400 ms → locked → 3 letters held → tap `Shift` → released | Unit | iPhone (simulator) | `swift test` for `StickyModifierState` transitions |
| Mode toggle preserves Compose draft both directions | Unit (model) | iPhone (simulator) | `swift test` for `RemoteInputDock` model |
| Direct mode entry dismisses iOS keyboard and shows custom keyboard | XCUITest | iPhone (simulator) | XCUITest screenshot diff |
| One-time-per-session warning appears on first Direct entry, not on subsequent toggles | XCUITest | iPhone (simulator) | XCUITest assertion |
| Hardware keyboard chord (`Ctrl-C`) over `UIKeyCommand` produces same wire bytes as on-screen `Ctrl`+`c` | Unit | iPhone (simulator) | `swift test` against shared `KeysymMapping` |
| Persistent "Direct mode" badge visible on session HUD when keyboard is collapsed | XCUITest | iPhone (simulator) | XCUITest screenshot |
| Real Mac VNC + Bluetooth Magic Keyboard: vim navigation `Esc h j k l : w q` works end-to-end | Manual device | iPhone (physical) | Manual device test log + short screen recording |
| Real Mac VNC: shell pipeline `Tab` completion + `Ctrl-R` history search work | Manual device | iPhone (physical) | Manual device test log |
| Sticky modifier visual states (idle / armed / locked) are distinct on iPad too | Manual | iPad-graceful (simulator) | Screenshot |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can drive a remote `vim` session on iPhone using only the custom on-screen keyboard — open, navigate, save, quit — without any required key being unreachable from the QWERTY page or special-keys page.
- **SC-002**: A user can run a shell pipeline on iPhone with `Tab` completion, `Ctrl-C` cancellation, `Ctrl-R` reverse search, and arrow-key history navigation — all reachable without leaving the session view.
- **SC-003**: From an active session, mode toggle is reachable in **≤ 2 taps**.
- **SC-004**: Per-key latency from on-screen tap completion to RFB `KeyEvent` write completion is **≤ 16 ms** at the 95th percentile on iPhone 17 Pro (one render-frame budget).
- **SC-005**: When a Bluetooth / Magic Keyboard is attached and Direct mode is active, hardware keystroke `KeyEvent` bytes are byte-for-byte identical to the on-screen path's bytes for the same logical key — verified by a unit test that exercises both paths against a fake RFB recorder.
- **SC-006**: No keystroke content (keysym, scancode, character) appears in any diagnostic export, log file, or telemetry payload — verified by a static check + `DiagnosticExport` rendering test extension.

## Assumptions

- Remote VNC server speaks RFB 3.8 `KeyEvent` (RFC 6143 §7.5.4). Existing in MVP and verified by `FakeRFBServer` fixtures.
- The remote application accepts X11 keysym deliveries — Naru does not detect remote focus state (same boundary as Compose & Send).
- iPhone first per constitution §VI; iPad is graceful scaling, not the design pivot.
- QWERTY page is **English-only**. Korean / CJK / emoji input remains exclusively on Compose & Send (constitution §I default; this is documented as a Non-Goal below, not a deferral).
- Sticky modifiers cover Ctrl / Shift / Alt / Cmd. CapsLock, Fn, and Globe are out of scope for v1 — they have no consistent X11 keysym across remote OS targets.
- Hardware keyboard support is iPad-and-iPhone-with-attached-keyboard; no extra hardware is required for shipping. The on-screen keyboard remains the primary path on iPhone.
- The 400 ms double-tap window is a UI default; tuning belongs to plan / implementation, not a scope variable.

## Non-Goals

- **Floating / repositionable keyboard UI** — explicitly deferred. Bottom-docked only. (Chosen by founder 2026-05-02 to keep v1 small.)
- **IME composition inside Direct mode** — Compose & Send remains the IME-friendly path. No Hangul assembly, no kana conversion, no autocorrect, no dictation in Direct mode. Constitution §I.
- **Voice input, image paste, file drop, helper insertion, agent handoff** — all remain Phase 9 post-MVP, separate features.
- **Auto-detection of remote terminal vs GUI** — user picks the mode. Naru does not introspect remote app state.
- **Remote secure-input detection** — Naru cannot detect macOS Secure Keyboard Entry or password fields; the persistent on-screen badge is the disclosure boundary.
- **Naru-side auto-repeat for hardware keyboards** — the remote OS owns auto-repeat once a `KeyEvent` down is held.
- **CapsLock, Fn, Globe, dictation, Siri activation keys** — no consistent X11 keysym mapping, deferred.
- **macOS-style Cmd-key system shortcuts that don't map to X11** (e.g., screenshot, dictation) — deferred.
- **Persisting Direct mode across disconnect / app relaunch** — always resets to Compose on session start (constitution §I default).
