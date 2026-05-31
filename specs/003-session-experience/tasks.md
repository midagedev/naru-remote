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
- [~] T003 [A] `SessionViewportView` — **partial**: now renders at the server's TRUE aspect ratio (`containerAspectRatio`, clamped [0.5,2.5]) instead of hardcoded 4:3, verified via 16:9 sim screenshot. STILL TODO: full screen-first hero layout (move pills/diagnostics out of the stack into a control bar / disclosure).
- [x] T004 [A] `MetalFramebufferHostingView` — 1-finger pan when zoomed (LOCAL, no RFB), double-tap zoom toggle, zoom/pan synced from parent. **Done** (build-green).
- [ ] T005 [A] `SessionControlBar.swift` — compact overlay: disconnect, zoom-reset, status chip + quality. **TODO** (controls still in the SessionViewportView header).
- [~] T006 [A][VISUAL] Screenshots saved: `artifacts/screenshots/session-experience/A-widescreen-iphone-light.png` (16:9 fills width — verified) + `A-empty-placeholder-iphone-light.png`. Hero-layout reshoot pending T003/T005.

## Stage B — Trackpad mode + cursor
- [x] T010 [P][B] `TrackpadCursor` + `PointerControlMode` + `RFBPointerCommand` in Core (`PointerControl.swift`). **Done.**
- [x] T011 [P][B] `PointerControlTests.swift` — 6 tests (relative move scaled by displayScale, clamp, centered, click pair, clamp rounding). **Done.**
- [x] T012 [P][B] `PointerGestureResolver` in Core — pure decision table → `(cursor', transform', [RFBPointerCommand])`. **Done.**
- [x] T013 [P][B] `PointerGestureResolverTests.swift` — 10 tests (direct tap through zoom+pan; trackpad tap@cursor; 2-finger@cursor; tap-and-a-half; zoom/pan → `[]`; auto-pan). **Done.**
- [ ] T014 [B] Wire `pointerControlMode`, `trackpadCursor` on `NaruRemoteAppModel`; route gestures through the resolver; dispatch commands via `activePointerClient`; reset on disconnect/profile-change/connect. **TODO — next big item (core is ready).**
- [ ] T015 [B] `TrackpadCursorView` overlay + trackpad gestures in `MetalFramebufferHostingView`; auto-pan-to-cursor when zoomed; mode toggle in control bar. **TODO.**
- [ ] T016 [B][VISUAL] Screenshots: trackpad cursor visible, direct mode (no cursor), mode toggle. **TODO.**

## Stage C — Connection quality + compose quick keys
- [x] T020 [P][C] `ConnectionQuality` + `ConnectionQualityEstimator` in Core. **Done.**
- [x] T021 [P][C] `ConnectionQualityTests.swift` — 7 tests (bucket thresholds, EMA, reset, unknown-on-empty). **Done.**
- [~] T022 [C] Latency sampled in the stream loop → `@Published connectionQuality` on the model, reset on connect/disconnect/profile-change. **Done (model, build-green).** TODO: surface the chip in the control bar (waits on T005).
- [x] T023 [C] Inline Compose quick-key strip (Esc/Tab/⌃C/↑/↓) in `RemoteInputDockView`, dispatch via `model.sendComposeQuickKey`, draft untouched, gated on active session. `ComposeQuickKeyTests` (7) + `ComposeQuickKeyModelTests` (2). **Done.**
- [~] T024 [C][VISUAL] `C-quickkeys-iphone-light.png` saved (Image-Read tool flaky mid-session; visual judge pending). Chip screenshots wait on T005.

## Cross-cutting
- [ ] T030 Re-capture the UX-audit screenshot set; document intentional layout diffs in the PR.
- [ ] T031 Update `ROADMAP.md` (new "Phase 11 — Session Experience" or extend Phase 5/6 notes) + `PRODUCT_SPEC.md §6.2` to reflect shipped pointer modes / zoom-pan / screen-first viewport.
- [ ] T032 [Manual] Real Mac VNC trackpad + zoom-to-read on physical iPhone — BLOCKED (no device); record residual risk per constitution §III.

## Dependencies
Stage A core (T001/T002) → A app (T003–T006). Stage B core (T010–T013) parallel with A app; B app (T014–T016) needs A app + B core. Stage C is independent of B and can overlap. VISUAL tasks wait on their stage's app tasks.
