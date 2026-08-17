# Feature Specification: Simplified Input UX (Orca-Modeled)

**Feature Branch**: `011-simplified-input-ux`
**Created**: 2026-07-17
**Status**: Implemented (2026-08-17) — two-mode Type/Compose dock, shared accessory strip, immediate-click gestures, tools-menu declutter; `swift test` 1509/1509 green; residuals below.
**Product**: Naru Remote
**Input**: Founder feedback 2026-07-17 — features sprawled, UX tangled; keyboard/mouse input and gestures do not behave as expected. Keyboard input should follow the cloned orca mobile companion's input model (`~/repo/orca/mobile/src/terminal/`): direct input default, accessory key strip above the keyboard, buffered compose as the opt-in, immediate gesture dispatch.

## Problem

1. **Three coexisting input modes** (Compose / Live / Direct) with a segmented picker, three floating toggles, a Direct entry-warning dialog, a Direct "input surface" menu (Naru/iOS/HW), a custom on-screen keyboard with two pages, live disclosure badges, and quick-key strips. Choosing "how do I type" is a research project.
2. **Default mode is buffered** — an interactive session (terminal, prompt, password field) requires the user to know that Live or Direct exists. Orca's lesson: type-through should be the default; buffered compose is the opt-in.
3. **Gestures**: every single tap waits for the double-tap zoom window (~350 ms) and the long-press failure window before the click is dispatched — taps feel dead or swallowed. Double-tap currently zooms instead of double-clicking. Two-finger tap (right click) is inert in direct-touch mode.
4. **Session chrome**: the session tools menu exposes five stream-experiment toggles (compose delivery, stream power, encoding, startup preflight, startup glance scale) at the same level as Checks and PiP Watch.

## Ground Truth Enabling This Change

- Unicode X11 keysym type-through **renders on macOS Screen Sharing** (measured 2026-07-13; overturned the earlier `no-input` measurement). Compose default delivery is already `keystrokeStream`. Live mode's Unicode-keysym ladder is therefore a fully-VNC primary typing path.
- Founder decision D3 (NEXT_STEPS P0 #4) authorizes promoting type-through to the default multilingual path and amending constitution §I accordingly.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Connect And Just Type (Priority: P0)

The user connects to their Mac and taps the keyboard affordance. The system keyboard opens with their Korean IME. Typed text lands at the remote insertion point as it commits — no mode research, no Send tap, no warning dialog.

**Acceptance Scenarios**:

1. **Given** a fresh active session, **When** the user opens the input dock, **Then** the dock is in **Type (type-through)** mode — the mode Live type-through previously named — with the Compose editor available via a single toggle.
2. **Given** Type mode, **When** the user types Korean with the IME, **Then** committed text streams through the existing Live delivery ladder (helper `nativeInsert` when paired, Unicode-keysym stream otherwise); marked text stays local.
3. **Given** Type mode, **When** a hardware (Bluetooth) keyboard is attached, **Then** text keys flow through the editor as typed and special keys (Esc/Tab/arrows/F-keys) emit keysyms through the hardware responder attached to Type mode.

### User Story 2 — Terminal Keys One Tap Away (Priority: P0)

While typing, the user needs Esc, Tab, Ctrl, arrows, or F-keys. An accessory strip — modeled on orca's terminal accessory keys — sits directly above the editor/keyboard in **both** Type and Compose modes: `Esc · Tab · ⌃ · ⌥ · ⌘ · ← ↑ ↓ → · Del` with an Fn expansion (`F1–F12, Home, End, PgUp, PgDn, Ins, ⌫, ↵`). Sticky modifiers (⌃⌥⌘, single-tap arm / double-tap lock) wrap the next strip emission.

**Acceptance Scenarios**:

1. **Given** any dock mode, **When** the user taps a strip key, **Then** the keysym (plus any armed/locked sticky modifiers) is emitted through the same `KeystrokeEmitter` path as the old Direct keyboard and quick keys; armed modifiers release after the emission.
2. **Given** the strip, **When** the user taps ⌃ then `c`, **Then** the wire envelope is `Ctrl down → c down → c up → Ctrl up` — byte-identical to the old Direct armed-Ctrl path.
3. **Given** no active session, **When** the dock is not mounted, **Then** no strip exists (the dock is session-only).

### User Story 3 — Taps Behave Like A Mouse (Priority: P0)

Mouse input matches platform conventions (orca lesson: dispatch immediately, disambiguate never):

| Gesture | Behavior |
| --- | --- |
| Single tap | Immediate left click — no double-tap or long-press wait |
| Double tap | Second left click at the same point (remote double-click) |
| Long-press (0.5 s) | Right click (both pointer modes) |
| Two-finger tap | Right click (both pointer modes) |
| One-finger drag | Direct mode: remote drag at the touched point · Trackpad mode: relative cursor move |
| Two-finger drag | Remote scroll (wheel) |
| Pinch | Local zoom only (never an RFB message) |

**Acceptance Scenarios**:

1. **Given** direct-touch mode, **When** the user taps once, **Then** the click dispatches immediately (tap recognizer has no failure requirements on double-tap/long-press/two-finger-tap).
2. **Given** any mode, **When** the user double-taps, **Then** exactly two left clicks are dispatched and no zoom change occurs; zoom remains pinch-only.
3. **Given** direct-touch mode, **When** the user two-finger taps, **Then** a right click is dispatched (previously trackpad-only).

### User Story 4 — A Session Screen You Can Read (Priority: P1)

The immersive control bar keeps Connections / Disconnect / Pointer mode / Tools. The tools menu top level is `Checks · PiP Watch · Advanced ▸`; the five stream-experiment toggles move under Advanced.

**Acceptance Scenarios**:

1. **Given** an active session, **When** the user opens session tools, **Then** Checks and PiP Watch are top-level and all stream toggles are nested under one Advanced submenu.

## Scope

**In**:
- Dock reduced to two modes: Type (= Live type-through, default) and Compose. `.direct` removed from the dock mode enum; Direct-only UI surfaces deleted (custom keyboard grid, input-surface menu, entry warning, IME-off badge, segmented mode picker, floating Direct toggle).
- `DirectKeystrokeMode` sticky-modifier state + `KeystrokeEmitter` retained and reused by the accessory strip and hardware responder.
- New `AccessoryKey` core model (keysyms + labels + sticky wrapping) shared by both modes; `ComposeQuickKey` compose actions (⌫/↵) remain compose actions.
- Hardware-key responder attaches while Type mode is active.
- Gesture recognizer fixes per User Story 3.
- Tools-menu Advanced submenu.
- Constitution §I amendment per founder D3; NEXT_STEPS update.

**Out of scope**: helper packaging (spec P1 item), non-macOS ladders, PiP input, new settings screens, trackpad-vs-direct default change (keeps `.directTouch` default + control-bar toggle).

## Verification Matrix

- Unit: AccessoryKey emission + sticky wrap; two-mode dock enum; Type-default on session start; strip visibility gating.
- Existing: LiveTypeThroughRoutingTests, DirectKeystrokeModeTests (sticky state retained), ComposeQuickKeyModelTests.
- Gesture: recognizer-configuration unit coverage where possible; simulator manual pass documented as residual if not automatable.
- iPhone simulator build (canonical target) + `swift test` green; UX screenshot suite re-run; residuals recorded here.

## Residuals

- Physical-iPhone pass (Korean IME through Type default, accessory strip +
  sticky modifiers, immediate single/double/right-click feel, Bluetooth
  keyboard) — NEXT_STEPS P0 #1.
- UX screenshot suite re-run on simulator (`UXAuditScreenshotsUITests`) —
  Direct-mode captures were replaced by accessory-strip/Type captures and
  need a fresh evidence run.
- `DirectKeystrokeMode` model state and its XCTest surface are retained
  (diagnostics `directKeystrokeModeActive`, snapshot mirror); retire them
  with a dedicated cleanup once no diagnostic consumer reads the field.
- iPad landscape store capture for the Fn strip (`testStoreIPadAccessoryStripFn_light`)
  replaces the old Direct special-page capture.

## Live simulator E2E against the local Mac — investigation log (2026-08-17)

The app-side E2E (`LocalMacConnectE2EUITests.testTypeMode_typesPayloadLive`,
plus `testComposeSend_typesThroughUnicodeKeysyms` as the control) connects
and passes its local-mirror assertions, but keystrokes do NOT land on the
Mac. Root-caused to the macOS side, not the app:

1. **The VNC viewer is handed an off-console loginwindow session.**
   `screensharingd` logs `uid -2 wantConsole 0 createLoginWindow 1 ...
   found off console loginwindow session`, and the served framebuffer's
   luminance map (via the `FrameSizeProbe` tool) shows the loginwindow
   avatar block — NOT the console desktop, even though ServerInit reports
   the real display size and a first frame streams fine.
2. **Keystroke injection is refused there.** `ScreensharingAgent` logs
   `do not send since at loginwindow` and `viewer did not set keyboard
   source` on every KeyEvent probe (including the previously-verified
   `VNCLiveBenchmark --text-keystroke-probe-only` path — app-independent).
3. Remedies tried from this repo (all via `kickstart`, admin password via
   osascript indirection): `-access -on -privs -all`, specifiedUsers
   config with `-setvnclegacy -vncpw`, and
   `VNCAlwaysStartOnConsole=1`. The viewer is still routed to the
   loginwindow session after each restart.
4. Environment deltas vs the working 2026-07-13 measurement: Screen
   Sharing was re-enabled this session via launchctl + kickstart (it was
   off); `ScreenSharingReqPermEnabled=1` (macOS remote-control approval);
   a stale off-console loginwindow session (`loginwindow/96412`) exists.
   The 2026-07-13 run worked with the same client code, so the server-side
   session routing is the variable.

**Tools added for this investigation** (keep for the next session):
- `NaruRemote/Tools/FrameSizeProbe` (SwiftPM executable): connects to the
  live VNC server, prints ServerInit, and prints a downsampled ASCII
  luminance map of the first frame so a text agent can see whether the
  served screen is the console desktop or the loginwindow. Env:
  `NARU_PROBE_HOST/PORT/PASSWORD`; `NARU_PROBE_TYPE` types a string +
  Return as per-scalar keysym pairs (attempted login-through; unverified —
  the probe run was cut short).
- `LocalMacConnectE2EUITests.testTypeMode_typesPayloadLive`: drives the
  full app against the live Mac (connect → floating strip → Type editor →
  type payload → local-mirror assert). Env: `NARU_E2E_HOST/PORT/PASSWORD`,
  `NARU_E2E_TYPE_TEXT` (default "Naru"). Screenshots to
  `NARU_E2E_OUTPUT_DIR`.

**Next-session entry point**: get `screensharingd` to attach the viewer to
the console session (login through the VNC loginwindow once with
`FrameSizeProbe`'s `NARU_PROBE_TYPE`, or clear the stale off-console
loginwindow session, or toggle Screen Sharing off/on in System Settings).
Then re-run the ascii and unicode-hangul probes via
`VNCLiveStimulusWindow --text-probe` (as a proper `.app` bundle — a bare
binary inherits `RoleNonUserInteractive` and cannot take focus) plus the
two E2E tests to verdict English and Korean type-through.
