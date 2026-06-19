# Feature Specification: Session Experience — Google-Remote-Desktop-Class Viewport & Pointer Control

**Feature Branch**: `003-session-experience`
**Created**: 2026-05-31
**Status**: Draft
**Product**: Naru Remote
**Input**: Goal — raise Naru Remote usability to **Google Remote Desktop** level. A phone-first user driving a remote desktop needs the remote screen to be the hero of the view, smooth and precise pointer control (a trackpad mode with a visible cursor, not finger-stab-only), and the ability to zoom in on small text and pan around — all without the current "control-panel" chrome (title + Checks/Connect/PiP pills + diagnostics panel + 4:3 letterbox inside a `ScrollView`). This feature replaces the presentation/interaction layer of `SessionViewportView`; it does **not** change the RFB protocol layer (encodings are tracked separately under `specs/004-rfb-encodings`).

## Why This Feature

The MVP can render frames, send absolute `PointerEvent`s (tap/long-press/drag/2-finger-scroll), and zoom locally with pinch. But measured against Google Remote Desktop, three things make Naru feel like a debug tool rather than a remote desktop:

1. The remote screen is constrained to a hardcoded **4:3 letterbox** (`SessionViewportView.body` → `.aspectRatio(4.0/3.0, contentMode: .fit)`) inside a vertical `ScrollView`, sharing the screen with a title, an action-pill row, a PiP chip, and a diagnostics summary. Real desktops are 16:9 / 16:10; the screen is small and not the focus.
2. Pinch zoom is a local `.scaleEffect` but there is **no way to pan** the zoomed view — the only 1-finger drag is a button-1 remote drag and 2-finger pan is bound to the scroll wheel. Zooming in to read terminal text traps the user.
3. Pointer control is **direct-touch only**: you stab where you want to click, your finger covers the target, and there is no cursor to aim. Google Remote Desktop's default is a **trackpad mode** — the finger moves a visible cursor relatively, tap = click — which is far more precise on a phone.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — The Remote Screen Is The View (Priority: P1)

A user connects to their Mac and the remote screen fills the available space at its **true aspect ratio**, edge to edge, like opening Google Remote Desktop. Connection controls and diagnostics are not stacked above/below the screen competing for space; they live in a compact, unobtrusive control surface that does not shrink the remote screen.

**Why this priority**: The remote screen being small and boxed is the first thing that reads as "not a real remote desktop." Everything else (pointer precision, zoom) only matters once the screen is the hero.

**Independent Test**: Connect against `FakeRFBServer` serving a 1920×1080 first frame on iPhone 17 Pro simulator; screenshot shows the remote framebuffer filling the session area at 16:9 (no 4:3 pillarbox), with controls in a compact bar rather than a stacked pill row + diagnostics panel pushing the screen up.

**Acceptance Scenarios**:

1. **Given** an active session with a 16:9 server framebuffer, **When** the session view renders on iPhone, **Then** the remote screen is presented at 16:9 (letterboxed only by the screen's own aspect mismatch, never by a hardcoded 4:3), filling the width and as much height as the layout allows.
2. **Given** an active session, **When** the user looks at the session view, **Then** session controls (disconnect, pointer-mode toggle, keyboard, zoom reset, connection status) are reachable from a single compact control bar that overlays or docks beside the screen without forcing the screen into a small box.
3. **Given** no session yet (a selected profile, not connected), **When** the detail view renders, **Then** a clear connect affordance and pre-connect status is shown, and the diagnostics detail remains accessible (e.g. via a disclosure / sheet) but is not stacked permanently under the screen.
4. **Given** an active phone session where strict aspect-fit would leave most of the live area empty, **When** the session renders, **Then** the viewport may start at a local crop-to-fill zoom baseline that preserves true aspect ratio and coordinate mapping, with panning available to inspect the cropped edges.

---

### User Story 2 — Pinch To Zoom And Pan Around (Priority: P1)

A user reading small terminal text pinches to zoom in, then drags with one finger to pan across the zoomed remote screen — and double-taps to toggle between fit and a comfortable zoom centered on the tapped point. Zoom and pan are **local** view transforms (constitution §I) and never produce RFB messages.

**Why this priority**: Zoom without pan is a trap; this is the #2 reason the current viewport frustrates a phone user reading code/terminal output.

**Independent Test**: Unit-test the pure `ViewportTransform` math — clamping scale to `[1.0, maxScale]`, clamping the pan offset so the zoomed content can never reveal background past its edges, and the double-tap zoom-to-point anchoring. Screenshot a zoomed + panned state.

**Acceptance Scenarios**:

1. **Given** the remote screen is at fit scale (1.0), **When** the user pinches out, **Then** the screen scales up about the pinch midpoint, clamped to a max scale.
2. **Given** the screen is zoomed in (> fit), **When** the user drags with one finger in **direct-touch** mode, **Then** the viewport pans and the pan offset is clamped so no out-of-bounds background is revealed.
3. **Given** the screen is zoomed in, **When** the user double-taps, **Then** the screen animates back to fit; **and given** at fit, a double-tap zooms to a comfortable scale centered on the tapped point.
4. **Given** any zoom/pan gesture, **When** it completes, **Then** no RFB `PointerEvent` / scroll message was emitted by the zoom or pan itself (constitution §I — local transform only).

---

### User Story 3 — Trackpad Mode With A Visible Cursor (Priority: P1)

A user switches the pointer mode to **Trackpad**. A cursor appears on the remote screen. One-finger drag moves the remote pointer relatively (like a laptop trackpad) by sending buttonless RFB pointer moves; a tap left-clicks at the cursor; a two-finger tap right-clicks; a two-finger drag scrolls. This is Google Remote Desktop's default and the precision win for phone control. **Direct-touch** mode (tap where you want to click) remains available via the toggle.

**Why this priority**: Trackpad-with-cursor is the single most recognizable Google Remote Desktop interaction and the biggest precision improvement for a small screen. Both modes share the same view→framebuffer mapping and RFB `PointerEvent` emission, so they must ship together to avoid a divergent second mapping later.

**Independent Test**: Unit-test the `PointerControlModel` — in trackpad mode a drag of (dx, dy) points moves the cursor by `round(dx * sensitivity)` framebuffer pixels clamped to `[0, width-1] × [0, height-1]`; a tap emits a button-1 down+up `PointerEvent` pair at the **cursor** position (not the touch position); a 2-finger tap emits a button-3 pair at the cursor. With `FakeRFBServer`, assert the recorded `(mask,x,y)` triples for a move→tap→2-finger-tap sequence.

**Acceptance Scenarios**:

1. **Given** trackpad mode is active, **When** the user drags one finger, **Then** the cursor moves relatively across the remote screen (clamped to the framebuffer bounds) and Naru emits buttonless (`0x00`) pointer-move events so the remote OS pointer follows without pressing any button.
2. **Given** trackpad mode with the cursor positioned, **When** the user taps once, **Then** Naru emits a button-1 `PointerEvent` down+up pair at the **cursor's** framebuffer coordinate.
3. **Given** trackpad mode, **When** the user taps with two fingers, **Then** Naru emits a button-3 (right-click) down+up pair at the cursor coordinate.
4. **Given** trackpad mode and the user wants to drag (select text / move a window), **When** they tap-and-hold then drag (tap-and-a-half), **Then** Naru emits button-1 down at the cursor, button-1 holds through the move, and button-1 up on release.
5. **Given** trackpad mode and the screen is zoomed in, **When** the cursor approaches a screen edge, **Then** the viewport auto-pans to keep the cursor visible.
6. **Given** the user switches to **Direct-touch** mode, **When** they tap the screen, **Then** Naru emits a button-1 pair at the **touched** framebuffer point (the existing behavior), and the trackpad cursor is hidden.
7. **Given** trackpad mode is active on iPad with a hardware trackpad or mouse, **When** the pointer hovers over the remote framebuffer, **Then** Naru maps the hover point through the shared viewport transform, updates the visible cursor, and emits a buttonless pointer move so remote hover feedback can update without waiting for a tap/drag.

---

### User Story 4 — Connection Status & Quality At A Glance (Priority: P2)

While connected, the user can see connection health (connecting / active / reconnecting / degraded) and a lightweight latency/quality indicator, without a verbose diagnostics panel taking permanent screen space. On a drop, the reconnecting state is obvious and non-blocking (no premature "failed").

**Why this priority**: Google Remote Desktop quietly shows connection state and reconnects; a phone user on cellular needs to trust the session is alive. This is polish on top of the existing `ReconnectPolicy` + `RemoteSessionState`.

**Independent Test**: Drive the model through `.connecting → .active → .reconnecting(1,3) → .active`; assert the control bar's status chip text/symbol/color for each, and that a round-trip latency sample (measured from frame-request to frame-arrival in the pump) is surfaced as a coarse bucket (Good / Fair / Poor) without logging any frame content.

**Acceptance Scenarios**:

1. **Given** an active session, **When** frames are flowing, **Then** a compact status chip shows "Connected" with a green indicator and a coarse quality bucket.
2. **Given** a transient drop, **When** the bounded auto-reconnect runs, **Then** the chip shows "Reconnecting (n/N)" with a spinner, and no "failed" copy appears while attempts remain.
3. **Given** a quality sample, **When** it is rendered, **Then** it is a coarse bucket only and no latency value, host, or frame content is written to any log or diagnostic export (constitution §IV).

---

### User Story 5 — Terminal-Essential Keys Without Leaving Compose (Priority: P3)

A user in Compose mode (the multilingual default) can reach an inline quick-key strip for Esc / Tab / Ctrl-C / arrows without switching to Direct mode, for the common "I'm composing Korean but need to hit Esc / Ctrl-C once" case. This is a convenience bridge, not a replacement for Direct mode's full keyboard.

**Why this priority**: Lower priority than the viewport/pointer core; it's a convenience that reduces mode-switching friction for the terminal/AI-CLI ICP. Constitution §I keeps Compose & Send the default multilingual path; this strip only sends discrete control keysyms via the existing `KeystrokeEmitter`.

**Independent Test**: With `FakeRFBServer`, tap the inline "Esc" and "Ctrl-C" quick keys while in Compose mode; assert the recorder shows the Esc down/up pair and the `Ctrl down → c down → c up → Ctrl up` sequence, and that the compose draft text is untouched.

**Acceptance Scenarios**:

1. **Given** Compose mode is active in a connected session, **When** the user taps the inline "Esc" quick key, **Then** Naru emits an Esc `KeyEvent` down/up pair and the compose draft is unchanged.
2. **Given** Compose mode, **When** the user taps the "Ctrl-C" quick key, **Then** Naru emits `Ctrl down → c down → c up → Ctrl up` and the compose draft is unchanged.
3. **Given** no active session, **When** the quick-key strip would render, **Then** it is hidden or disabled (no keysym is emitted with no connection).

### Edge Cases

- **Trackpad cursor at first connect**: cursor starts centered on the framebuffer; it persists across frames within a session and resets on disconnect / profile change.
- **Trackpad/input write backlog while typing**: bursty trackpad/cursor writes must not block Direct-mode key events, Compose quick keys, or later pointer gestures. Pointer and key events may share the same RFB socket, but the app-level outbound queues are independent so a slow cursor write cannot make the keyboard feel frozen. RFB user-input writes MUST enqueue to the transport without waiting for `contentProcessed`; ordering for clicks, drags, scroll, and key envelopes is preserved by the app-level lanes, while a single buttonless (`0x00`) trackpad cursor-follow move MAY additionally use a latest-value/best-effort path. A timed-out/stalled pointer operation MUST NOT clear the session's pointer capability or coordinate space; the next user gesture must retry on a fresh lane.
- **Mode switch mid-gesture**: switching pointer mode cancels any in-flight gesture cleanly; no stray button-up is emitted for a gesture that never sent a button-down.
- **Pinch + drag simultaneously**: pinch (zoom) and one-finger pan are distinct gestures; a 2-finger gesture is zoom/scroll, a 1-finger gesture is pan (direct) or cursor-move (trackpad). The view never emits a remote scroll while pinching.
- **Aspect ratio change (DesktopSize) mid-session**: when the server framebuffer dimensions change, the viewport recomputes fit scale and re-clamps the pan offset so the new size is fully framed (the protocol-level DesktopSize negotiation itself is `specs/004`).
- **PiP watch path**: PiP remains watch-only and does not install remote-input recognizers. When the main session viewport is zoomed/panned, the PiP renderer may mirror that local focus by cropping the video frames so the same area is readable in the floating window.
- **Sustained full-screen churn on iPhone**: when many consecutive content frames require full-frame renderer uploads, the stream may raise its pacing floor to the same power-saver cadence used for Low Power Mode. This protects thermals during video-like/full-desktop repaint workloads while preserving the faster cadence for localized terminal/IDE dirty rectangles.
- **Zoomed-in tap mapping (direct mode)**: a tap while zoomed/panned maps through the combined fit-scale × zoom × pan transform to the correct framebuffer pixel; letterbox bands remain a no-op (not a clamped edge click), preserving the existing behavior.
- **VoiceOver**: the remote screen exposes an accessibility element; pointer-mode toggle, zoom reset, and quick keys have labels. The framebuffer pixels are not described (privacy + meaningless).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The session view MUST present the remote framebuffer at the **server's true aspect ratio**, not a hardcoded ratio, sized to be the dominant element of the view (screen-first), with chrome that does not force the screen into a fixed small box. On constrained phone portrait layouts, it MAY use a local crop-to-fill zoom baseline instead of strict aspect-fit so the live stream occupies substantially more vertical space.
- **FR-002**: Session controls (disconnect, pointer-mode toggle, keyboard/compose access, zoom reset, connection-status chip) MUST be reachable from a compact control surface that overlays or docks without permanently shrinking the remote screen. Diagnostics detail MUST remain reachable (disclosure/sheet) but MUST NOT be permanently stacked under the screen. Overlay controls SHOULD auto-hide or collapse when idle so the remote screen remains the default visual state.
- **FR-003**: The user MUST be able to pinch-zoom the remote screen between fit scale and a max scale; zoom MUST be a local view transform and MUST NOT emit any RFB message (constitution §I).
- **FR-004**: When zoomed beyond fit, the user MUST be able to pan the viewport with a one-finger drag (in direct-touch mode); the pan offset MUST be clamped so no out-of-bounds region is revealed.
- **FR-005**: A double-tap MUST toggle between fit and a comfortable zoom centered on the tapped point; the animation MUST not emit any RFB message.
- **FR-006**: The user MUST be able to switch between **Direct-touch** and **Trackpad** pointer modes from the control surface in one tap. The choice persists for the session and resets to the product default on a fresh session start.
- **FR-007**: In **Trackpad** mode, a one-finger drag MUST move the visible cursor relatively (scaled by a sensitivity factor), clamped to `[0,width-1] × [0,height-1]` framebuffer pixels, and MUST emit buttonless (`0x00`) RFB pointer-move events so the remote OS pointer follows without pressing any button.
- **FR-008**: In **Trackpad** mode, a single tap MUST emit a button-1 down+up `PointerEvent` pair at the **cursor** coordinate; a two-finger tap MUST emit a button-3 pair at the cursor; a tap-and-a-half (tap then hold-drag) MUST emit button-1 down → hold-through-move → up.
- **FR-009**: In **Direct-touch** mode, a single tap MUST emit a button-1 pair at the **touched** framebuffer point (existing behavior); long-press MUST emit button-3 at the point; the trackpad cursor MUST be hidden.
- **FR-010**: Two-finger drag MUST emit RFB scroll-wheel events in both modes (existing behavior), distinct from pan.
- **FR-011**: In **Trackpad** mode while zoomed, the viewport MUST auto-pan to keep the cursor visible as it nears an edge.
- **FR-012**: A compact connection-status chip MUST reflect `RemoteSessionState` (connecting / active / reconnecting(n,N) / degraded / failed / closed) with distinct symbol + color, and MUST show a coarse connection-quality bucket (Good / Fair / Poor) derived from frame round-trip timing while active.
- **FR-013**: An inline quick-key strip in **Compose** mode MUST offer at least Esc, Tab, and Ctrl-C, emitting the correct `KeyEvent`(s) through the existing `KeystrokeEmitter`, without modifying the compose draft, and only while a session is active.
- **FR-014**: All view→framebuffer coordinate mapping (fit scale × zoom × pan, plus trackpad cursor position) MUST be a single shared, pure, unit-tested transform used by both pointer modes so the two paths cannot diverge.
- **FR-015**: While PiP Watch is active, local zoom/pan changes MUST update the PiP video focus without emitting RFB input. The output video dimensions SHOULD remain stable across focus changes to avoid PiP layer churn.
- **FR-016**: The app MUST isolate app-level outbound pointer and key queues. A stalled or timed-out pointer operation MUST NOT block or permanently disable later pointer gestures, Direct-mode key events, or Compose quick keys on the same active session. A stalled key operation MUST likewise release its own lane so later keys are retryable. RFB `PointerEvent` and `KeyEvent` delivery SHOULD return after transport enqueue rather than waiting for Network.framework `contentProcessed`; non-zero button masks and multi-command pointer gestures MUST still preserve down/move/up ordering through the ordered app-level pointer lane. Single buttonless trackpad cursor-follow moves MAY use a latest-value/best-effort capability.
- **FR-017**: In trackpad mode on iPad pointer hardware, hover movement over the viewport SHOULD update the local cursor and send a single buttonless (`0x00`) pointer move at the mapped framebuffer coordinate. This hover path MUST use the same `ViewportTransform` mapping as touch input and MUST NOT log or persist pointer coordinates.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001 Local composition path**: unchanged — Compose & Send remains the default multilingual path (constitution §I). This feature adds pointer/cursor control and a control-key convenience strip; it does not introduce a new text-composition path.
- **IN-002 Remote injection behavior**: pointer taps/clicks/right-clicks/drag/scroll emit RFB `PointerEvent` (RFC 6143 §7.5.5) via `RFBPointerEventClient`; single buttonless cursor-follow moves may use `RFBBestEffortPointerEventClient` when the active client supports it; quick keys emit `KeyEvent` (§7.5.4) via the existing `KeystrokeEmitter`. User-input events are ordered by app-level lanes and enqueue to the transport without waiting for `contentProcessed`. Zoom/pan emit nothing.
- **IN-003 Fallback behavior**: when the session is not `.active`, pointer and quick-key emissions are dropped silently (same boundary as today's pointer dispatch and Direct mode).
- **IN-004 Clipboard impact**: none. This feature does not read or write any clipboard.
- **IN-005 User confirmation**: none — pointer/cursor actions are direct manipulation. The pointer-mode toggle and zoom state are visible, reversible UI state.

### Tailnet / Connection Requirements

- **TN-001 Private-network assumption**: inherited from MVP; this feature rides on the existing VNC session.
- **TN-002 Diagnostics shown to user**: connection-quality bucket is derived from frame timing only; `PointerEvent`/`KeyEvent`/coordinate/latency content MUST NOT appear in any diagnostic export (constitution §IV).
- **TN-003 Public internet posture**: inherited from MVP — unchanged.

### Security & Privacy Requirements *(mandatory)*

- **SP-001 Data crossing local→remote**: pointer coordinates (already remote-pixel space at the RFB boundary) and control-key keysyms — same data classes as the existing pointer/Direct-mode paths. No new class crosses.
- **SP-002 Data retained on device**: pointer-mode preference and zoom/cursor state are in-memory session state (reset on disconnect/profile change). Quality buckets are transient. No coordinate, keysym, latency value, or frame content is persisted or logged (constitution §IV).
- **SP-003 Data retained on remote host**: unchanged — Naru does not control remote-side logging.
- **SP-004 Sensitive actions needing approval**: none new — direct manipulation of pointer/screen.
- **SP-005 Logging rule**: pointer coordinates, cursor position, scroll deltas, quick-key keysyms, and latency samples MUST NOT be written to any log, diagnostic, telemetry, or crash report. The diagnostic safe-detail catalog is unchanged.

### Key Entities *(include if feature involves data)*

- **ViewportTransform** — pure value type: fit-scale (framebuffer→view at content-fit), user zoom scale (clamped `[1.0, maxScale]`), pan offset (clamped so content edges stay flush). Maps view points ↔ framebuffer pixels. Single source of truth for both pointer modes (FR-014). Lives in `NaruRemoteCore` so it is `swift test`-able with no UIKit.
- **PointerControlMode** — enum `directTouch | trackpad`. Default product value applied on fresh session start.
- **TrackpadCursor** — framebuffer-pixel cursor position + visibility, with relative-move (sensitivity) and clamp logic. Pure, in `NaruRemoteCore`.
- **PointerControlModel** — turns a gesture (mode, gesture kind, view delta/point, current transform) into a cursor update and/or an RFB `PointerEvent` sequence. Pure logic in Core; the App layer wires gestures and dispatch.
- **ConnectionQuality** — coarse bucket (`good | fair | poor | unknown`) derived from a rolling frame round-trip timing sample. Pure; no value retained.

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI, every user-facing scenario lists an iPhone path before any iPad path.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Remote screen renders at server aspect (16:9), screen-first | XCUITest screenshot + unit | iPhone (simulator) | `ViewportTransform` fit-scale unit test; screenshot shows no 4:3 pillarbox |
| Pinch zoom clamps to `[1, max]`; pan offset clamps to bounds | Unit | iPhone (simulator) | `swift test` for `ViewportTransform` zoom/pan clamp |
| Double-tap toggles fit↔zoom-to-point | Unit + screenshot | iPhone (simulator) | `swift test` anchoring math; screenshot |
| Direct-touch tap maps through zoom+pan to correct framebuffer pixel | Unit + Fake RFB | iPhone (simulator) | recorder `(mask,x,y)` matches expected pixel |
| Trackpad drag moves cursor relatively, clamped, buttonless remote pointer move | Unit + Fake RFB | iPhone (simulator) | `swift test` for `TrackpadCursor` move/clamp and recorder `(0x00,x,y)` |
| Hardware pointer hover in trackpad mode maps to framebuffer and bypasses stalled pointer queue | Unit + Fake RFB | iPad (simulator) | resolver hover mapping test; app-model delayed reliable pointer queue regression |
| Trackpad tap → button-1 at cursor; 2-finger tap → button-3 at cursor | Unit + Fake RFB | iPhone (simulator) | recorder triples for move→tap→2-finger-tap |
| Trackpad tap-and-a-half → button-1 down/hold/up | Unit + Fake RFB | iPhone (simulator) | recorder down→move(0x01)→up sequence |
| Trackpad/input write backlog does not freeze keyboard or pointer lane | Unit + Fake RFB | iPhone (simulator) | delayed pointer/key writes; Direct key records promptly on separate lane; later pointer tap retries after a stalled pointer write |
| Pointer-mode toggle in one tap; cursor shown only in trackpad | XCUITest | iPhone (simulator) | screenshot of each mode |
| Status chip reflects each `RemoteSessionState`; quality bucket while active | Unit | iPhone (simulator) | `swift test` for chip mapping + `ConnectionQuality` bucketing |
| Compose quick keys (Esc / Ctrl-C) emit keysyms, draft untouched | Unit + Fake RFB | iPhone (simulator) | recorder `KeyEvent`s; model draft assertion |
| Zoom/pan emit no RFB message | Unit + Fake RFB | iPhone (simulator) | recorder empty after zoom/pan-only gestures |
| Screen-first layout + controls on iPad (graceful scaling) | Screenshot | iPad (simulator) | screenshot after iPhone path recorded |
| Real Mac VNC: trackpad precision + zoom-to-read terminal | Manual device | iPhone (physical) | Manual log (residual risk — no device in env) |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a 16:9 server framebuffer, the rendered remote screen occupies the full session width at the true aspect ratio with **no hardcoded 4:3 pillarbox** (verified by screenshot + `ViewportTransform` test).
- **SC-002**: A user can zoom in to read remote terminal text and pan across the whole screen; the pan offset never reveals out-of-bounds background (verified by `ViewportTransform` clamp tests).
- **SC-003**: In trackpad mode, a click lands within the intended target because the cursor is visible and positioned before the tap fires — tap emits at the cursor coordinate, not under the finger (verified by `PointerControlModel` + Fake RFB tests).
- **SC-004**: Pointer-mode toggle is reachable in ≤ 1 tap from the active session view (verified by screenshot / XCUITest).
- **SC-005**: Zoom and pan gestures produce **zero** RFB messages (constitution §I), verified by an empty `FakeRFBClientMessageRecorder` after a zoom/pan-only sequence.
- **SC-006**: No pointer coordinate, cursor position, scroll delta, quick-key keysym, or latency value appears in any diagnostic export / log (constitution §IV), verified by a `DiagnosticExport` rendering test extension + static review.

## Assumptions

- RFB `PointerEvent` coordinates are absolute framebuffer pixels (RFC 6143 §7.5.5) — trackpad mode still emits absolute coordinates derived from the cursor position, so no new wire semantics are introduced; the relativity is purely local cursor bookkeeping.
- The Metal renderer (`MetalFramebufferRenderer`) already supports aspect-fit presentation; this feature changes the SwiftUI framing and gesture layer, not the GPU upload path.
- iPhone first per constitution §VI; iPad is graceful scaling.
- Encodings, continuous updates, and DesktopSize pseudo-encodings are tracked in `specs/004-rfb-encodings`. Trackpad mode uses the server Cursor pseudo-encoding shape when the active connection provides it, with a synthetic cursor glyph only as a local fallback.

## Non-Goals

- **RFB encoding work** (CopyRect / Hextile / ZRLE / Tight), `SetEncodings` negotiation, continuous updates, Cursor / DesktopSize pseudo-encodings — `specs/004-rfb-encodings`.
- **Advanced hardware-trackpad parity on iPad** — pointer locking, custom pointer shape regions, modifier-aware pointer behavior, and full Magic Keyboard gesture customization remain layered enhancements. Basic hover-follow in trackpad mode is in scope as a small iPad graceful-scaling follow-up.
- **Multi-session / multi-view / session parking** — `specs/008` (ROADMAP Phase 8).
- **Replacing Direct Keystroke Mode** — the Compose quick-key strip is a convenience, not the full custom keyboard (`specs/002`).
- **Floating/repositionable control surface** — bottom/edge-docked or fixed overlay only in v1.
- **Gesture customization / sensitivity settings UI** — a single sensible default; tuning is a later setting.
