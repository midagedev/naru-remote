# Feature Specification: External Pointer Support & Accessory-Strip Completions

**Feature Branch**: `012-external-pointer-and-strip-completions`
**Created**: 2026-08-18
**Status**: Draft — approved scope from founder direction 2026-08-17 ("아이패드와 아이폰 모두에서 잘 쓸 수 있어야 하고 외부 블루투스 키보드 같은 거나 마우스로도 쓸 것을 고려해야해") + orca mobile reference study (`docs/research/orca-mobile-input-reference.md`) + lead UX audit (`scratch/ux-audit-2026-08-17.md`).
**Product**: Naru Remote
**Input**: Ship-quality audit findings HW-1/2/3 (mouse/trackpad gaps), orca reference P0 adoption calls (strip hold-repeat, one-tap ⌃C, IME-flush barrier), iPad dock width overflow.

## Problem

1. **A Bluetooth mouse or iPad trackpad cannot scroll or right-click the remote.**
   The remote-wheel pan recognizer (`MetalFramebufferView.swift`, two-finger pan)
   has no `allowedScrollTypesMask`, so indirect-pointer scroll events never reach
   it; no recognizer sets `buttonMaskRequired = .secondary`, so a physical
   right-click does nothing.
2. **Two cursors on iPad.** No `UIPointerInteraction` exists anywhere; the iPadOS
   system pointer floats over the remote view while the remote cursor moves
   separately. In direct-touch mode, hover is ignored entirely
   (`handleHoverGesture` guards `isTrackpad`), so moving a mouse does not move
   the remote cursor until a click lands.
3. **The accessory strip lacks three interaction behaviors** the orca reference
   measured as essential for terminal/AI-CLI use: hold-to-repeat on arrows/Del,
   a one-tap ⌃C interrupt (the model `ComposeQuickKey.controlC` exists but no
   strip button renders it), and an ordering barrier so a strip tap cannot fire
   while Korean IME composition is mid-flight (orca `commit-held-then-send` /
   control-after-flush ordering).
4. **The pinned dock stretches edge-to-edge on iPad** (regular width): mode
   picker, editor, and Send span ~1000+pt. `compactWindowWidth` caps only the
   compact size class. Constitution §VI requires iPad to scale gracefully.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Mouse And Trackpad Act Like A Mouse (Priority: P0)

An iPad (or iPhone) user attaches a Bluetooth mouse or uses the Magic Keyboard
trackpad. Pointer motion, wheel scroll, and secondary click drive the remote
exactly like touch gestures do.

**Acceptance Scenarios**:

1. **Given** an active session and an indirect pointer device, **When** the user
   scrolls (wheel or two-finger trackpad scroll) over the session view, **Then**
   remote wheel events dispatch through the same scroll handler as the
   two-finger touch drag (a dedicated pan recognizer with
   `allowedScrollTypesMask = .all`, `maximumNumberOfTouches = 0`).
2. **Given** an indirect pointer device, **When** the user secondary-clicks
   (right button or two-finger trackpad click), **Then** a remote right click
   dispatches at the pointer location (tap recognizer with
   `buttonMaskRequired = .secondary`), and the primary tap recognizer never
   interprets it as a left click.
3. **Given** hover over the session view, **When** the pointer moves, **Then**
   the remote cursor follows in **both** pointer modes (direct-touch included —
   hover implies an indirect device), and the system pointer hides over the
   session view (`UIPointerInteraction` with `.hidden` style) so only the
   remote cursor is visible.
4. **Given** the session view loses hover (pointer leaves the view), **Then**
   the system pointer reappears.

### User Story 2 — Strip Keys Behave Like Keyboard Keys (Priority: P0)

**Acceptance Scenarios**:

1. **Given** the accessory strip, **When** the user holds an arrow key or Del,
   **Then** the key repeats: one emission on touch-down, then after 400 ms an
   emission every 45 ms until release (orca cadence). Esc/Tab/F-keys and all
   destructive-if-held keys do NOT repeat. Repeat stops on release, on strip
   unmount, and on session teardown.
2. **Given** the primary strip row, **When** the user taps the ⌃C key, **Then**
   the wire envelope is `Ctrl down → c down → c up → Ctrl up` (the existing
   `ComposeQuickKey.controlC` emission), independent of sticky-modifier state.
3. **Given** an iPhone-width strip, **When** the session is live, **Then** the
   keys an AI-CLI session needs most — the four sticky modifiers, Esc, Tab, and
   ⌃C — are all reachable without horizontal scrolling. Modifiers render in
   macOS glyph notation (⌃ ⌥ ⌘ ⇧) at 36 pt so the row fits; VoiceOver still
   announces the modifier kind and slot state.
4. **Given** Type mode with Korean IME composition in progress (marked text),
   **When** the user taps any strip key or quick key, **Then** the pending
   composition is committed (or the pending live insert drained) **before** the
   keysym emits — the emission never interleaves ahead of in-flight text. If
   the flush fails, the control key is not sent (orca
   `sendTerminalLiveControlAfterPendingFlush` contract).

### User Story 3 — iPad Dock Reads As A Dock (Priority: P1)

**Acceptance Scenarios**:

1. **Given** an iPad in regular width, **When** the pinned dock (standard or
   compact form) is visible, **Then** its content column is capped at 720 pt
   and centered (orca `CONTENT_MAX_WIDTH` analog); iPhone/compact behavior is
   unchanged.

## Scope

**In**: dedicated scroll-wheel pan recognizer; secondary-click tap recognizer;
`UIPointerInteraction` hidden-style + hover-to-remote-cursor in both pointer
modes; strip hold-repeat (`AccessoryKey.repeatable`); ⌃C strip button rendering
the existing `ComposeQuickKey.controlC` emission; IME/pending-flush barrier in
`sendAccessoryKey`/`sendComposeQuickKey`; iPad regular-width dock cap (720 pt).

**Out of scope**: custom user-defined keys (orca CustomKeyModal analog — future
spec), strip layout persistence, dictation routing, Enter/Space/Shift+Tab strip
keys (P2 backlog), pointer lock, external-display targeting.

## Verification Matrix

- Unit (`swift test`): `AccessoryKey.repeatable` set; repeat-cadence state
  machine (400/45 ms, stop conditions); flush-barrier ordering (marked-commit /
  drain before emission; no emission on flush failure); ⌃C envelope equality
  with sticky ⌃+`c`; dock width-cap policy function.
- Recognizer configuration unit coverage where possible (scroll mask, button
  mask, hover mode gating).
- iPhone simulator: build + UX screenshot suite green (canonical target first,
  constitution §VI).
- iPad simulator: build + dock width-cap capture (regular width).
- **Physical-device residual**: real Bluetooth mouse/trackpad scroll, secondary
  click, and pointer-hide need a physical iPad; hold-repeat feel and IME-flush
  barrier need a physical iPhone with Korean IME. Record as residuals if not
  run before merge.

## Residuals

- (fill at implementation time)
