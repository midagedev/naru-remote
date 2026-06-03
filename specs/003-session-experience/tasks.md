---
description: "Tasks: Session Experience — GRD-Class Viewport & Pointer Control"
---

# Tasks: Session Experience (003)

**Input**: `spec.md`, `plan.md` in `/specs/003-session-experience/`
**Format**: `[ID] [P?] [Stage] Description` — `[P]` = parallelizable (disjoint files). Every impl task names the test/evidence that closes it.

## Stage A — Core transform + screen-first viewport

### Core (pure, swift test)
- [x] T001 [P][A] `ViewportTransform` in `NaruRemote/Sources/NaruRemoteCore/SessionViewer/ViewportTransform.swift` — fitScale, displayScale, contentOrigin, view↔framebuffer mapping (letterbox→nil), pan clamp, `zoomed(to:about:)`, `panned(by:)`, `panToReveal`. **Done.**
- [x] T002 [P][A] `ViewportTransformTests.swift` — 10 tests passing (fit-scale 16:9, round-trip, pan clamp, zoom-about-anchor, max-clamp, reset, panToReveal). **Done.**

### App (SwiftUI)
- [x] T003 [A] `SessionViewportView` — live sessions now use a screen-first hero surface: no scroll wrapper, no title/header stack, framebuffer pinned to the top of the available stream area, and diagnostics kept off the live stack. Verified via UX-audit 16/17 iPhone captures. **Done.**
- [x] T004 [A] `MetalFramebufferHostingView` — 1-finger pan when zoomed (LOCAL, no RFB), double-tap zoom toggle, zoom/pan synced from parent. **Done** (build-green).
- [x] T005 [A] `SessionControlBar.swift` — compact live-session overlay implemented in `SessionViewportView` with status, quality, checks, disconnect, pointer-mode, and PiP controls. **Done.**
- [x] T006 [A][VISUAL] Screenshots saved: `artifacts/screenshots/ux-audit/16-session-active-widescreen-iphone-light.png`, `16-session-active-widescreen-iphone-dark.png`, `17-session-active-keyboard-iphone-light.png`, `17-session-active-keyboard-iphone-dark.png`. **Done.**
- [x] T007 [A] `SessionViewportView` — active phone sessions start at a local crop-to-fill/zoom-fill baseline when strict aspect-fit would waste most of the live area, and the top live control bar auto-hides to a reveal handle. Unit-covered by `SessionViewportViewGeometryTests`; screenshot refresh pending in T030. **Done.**

## Stage B — Trackpad mode + cursor
- [x] T010 [P][B] `TrackpadCursor` + `PointerControlMode` + `RFBPointerCommand` in Core (`PointerControl.swift`). **Done.**
- [x] T011 [P][B] `PointerControlTests.swift` — 6 tests (relative move scaled by displayScale, clamp, centered, click pair, clamp rounding). **Done.**
- [x] T012 [P][B] `PointerGestureResolver` in Core — pure decision table → `(cursor', transform', [RFBPointerCommand])`. **Done.**
- [x] T013 [P][B] `PointerGestureResolverTests.swift` — 10 tests (direct tap through zoom+pan; trackpad tap@cursor; 2-finger@cursor; tap-and-a-half; zoom/pan → `[]`; auto-pan). **Done.**
- [x] T014 [B] Wire `pointerControlMode`, `trackpadCursor` on `NaruRemoteAppModel`; route gestures through the resolver; dispatch commands via `activePointerClient`; reset on disconnect/profile-change/connect. **Done.** Model now also accepts the live `ViewportTransform` from the view so trackpad cursor motion and auto-pan account for current zoom/pan.
- [x] T015 [B] `TrackpadCursorView` overlay + trackpad gestures in `MetalFramebufferHostingView`; auto-pan-to-cursor when zoomed; mode toggle in control bar. **Done.** The cursor overlay uses the same fit × zoom × pan transform as the framebuffer, model-returned auto-pan is fed back into the view/PiP focus path, and active PiP watch disables remote trackpad input so the preview can be used as a local zoom/pan focus controller.
- [x] T015a [B] Trackpad drag now sends coalesced buttonless (`0x00`) RFB pointer moves so the remote OS cursor follows the local trackpad cursor without pressing a button. Pinch zoom now anchors on the recognizer midpoint for Photos-like navigation. **Done in PR branch.**
- [x] T016 [B][VISUAL] Screenshots: trackpad cursor visible, direct mode (no cursor), mode toggle. **Done.** Direct mode/no-cursor is covered by `16-session-active-widescreen-iphone-{light,dark}.png`; trackpad/server-cursor overlay is covered by `18-session-active-trackpad-cursor-iphone-{light,dark}.png`.

## Stage C — Connection quality + compose quick keys
- [x] T020 [P][C] `ConnectionQuality` + `ConnectionQualityEstimator` in Core. **Done.**
- [x] T021 [P][C] `ConnectionQualityTests.swift` — 7 tests (bucket thresholds, EMA, reset, unknown-on-empty). **Done.**
- [x] T022 [C] Latency sampled in the stream loop → `@Published connectionQuality` on the model, reset on connect/disconnect/profile-change, surfaced in the live control overlay. **Done.**
- [x] T023 [C] Inline Compose quick-key strip (Esc/Tab/⌃C/↑/↓) in `RemoteInputDockView`, dispatch via `model.sendComposeQuickKey`, draft untouched, gated on active session. `ComposeQuickKeyTests` (7) + `ComposeQuickKeyModelTests` (2). **Done.**
- [x] T024 [C][VISUAL] Quality chip and compact quick-key menu covered by the active-session UX-audit captures (`16-*` and `17-*`). **Done.**

## Cross-cutting
- [~] T030 Re-capture the UX-audit screenshot set; active-session light/dark + keyboard captures refreshed for this PR. Full UX-audit set still pending a broader pass.
- [ ] T031 Update `ROADMAP.md` (new "Phase 11 — Session Experience" or extend Phase 5/6 notes) + `PRODUCT_SPEC.md §6.2` to reflect shipped pointer modes / zoom-pan / screen-first viewport.
- [ ] T032 [Manual] Real Mac VNC trackpad + zoom-to-read on physical iPhone — BLOCKED (no device); record residual risk per constitution §III.

## Dependencies
Stage A core (T001/T002) → A app (T003–T006). Stage B core (T010–T013) parallel with A app; B app (T014–T016) needs A app + B core. Stage C is independent of B and can overlap. VISUAL tasks wait on their stage's app tasks.
