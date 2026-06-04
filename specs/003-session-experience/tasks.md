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
- [x] T015b [B] Smooth viewport hotfix: keep UIKit pinch/zoomed-pan accumulators from being overwritten by frame-driven SwiftUI updates during an active gesture, pass the immersive crop-to-fill baseline zoom into the UIKit recognizer, preserve pinch anchor pan inside the host view, remove spring animation from trackpad auto-pan, and disable implicit animation on continuous preview scale/offset updates. **Done.**
- [x] T015c [B] Physical iPhone follow-up: apply Metal zoom/pan directly inside the UIKit `MTKView` host during gestures, use a wider viewport-relative trackpad auto-pan follow zone, and run Compose clipboard/paste injection off the main actor so delayed VNC writes do not stall the keyboard/input dock. **Done.**
- [x] T015d [B] Physical iPhone smoothness follow-up: host trackpad tap/drag/right-click gestures directly in `MetalFramebufferHostingView` when Metal is available so the hot path avoids SwiftUI `DragGesture` overlay churn, apply returned auto-pan to the `MTKView` immediately, coalesce direct pinch/pan state mirroring to SwiftUI/PiP, and use a compact `TextEditor` for Compose to improve Korean/CJK marked-text entry above the keyboard. **Done.**
- [x] T015e [B] Physical iPhone correction: make the Metal host clamp and anchor local zoom/pan through the same `ViewportTransform` used by pointer/cursor mapping, and replace Compose's SwiftUI-only text editor path with a UIKit `UITextView` wrapper plus model draft synchronization so Korean/CJK marked text and in-flight send edits are not overwritten. **Done.**
- [x] T015f [B] Physical iPhone follow-up: suppress remote scroll while pinch is active, disable implicit animations on hot-path Metal viewport transforms, start zoomed trackpad auto-pan earlier with a wider follow zone, and commit iOS marked text before Compose Send without dismissing the keyboard. **Done.**
- [x] T015g [B] Physical iPhone correction: mirror Metal zoom/pan/trackpad auto-pan state to SwiftUI on `CADisplayLink` ticks instead of per-event async sleeps, stop the Metal trackpad path from synchronously mutating `SessionViewportView` state on every drag sample, and make Compose Send synchronously commit/read the active `UITextView` so Korean/CJK marked text is not lost to a notification/yield race. **Done.**
- [x] T015h [B] Physical iPhone correction: add velocity-based deceleration to zoomed direct-touch pan, coalesce trackpad cursor publishing to display-frame cadence while keeping resolver state immediate, clear Compose drafts after the paste command leaves the device, and restore seeded input-dock UI-test entry after the grid-first launch change. **Done.**
- [x] T015i [B] Physical iPhone correction: defer SwiftUI/PiP viewport-state mirroring for direct pinch, zoomed pan, and pan deceleration until the gesture settles, keeping the visible movement on the UIKit/Metal transform path while VNC frame-stream diffs continue. Local redacted live benchmark evidence recorded in `artifacts/benchmarks/2026-06-04-post-inertia-viewport-live-summary.md`. **Done.**
- [x] T015j [B] Physical iPhone correction: throttle incoming framebuffer redraws while a local viewport gesture is active so large Metal uploads cannot starve pinch/pan touch tracking; flush the latest deferred frame when the gesture settles. Covered by `ViewportGestureRedrawThrottleTests`. **Done.**
- [x] T015k [B] Physical iPhone correction: move zoom/pan projection into `MetalFramebufferRenderer` draw geometry instead of transforming the `MTKView` layer, redraw the current texture immediately during gestures, suspend pending framebuffer uploads while the viewport is moving, and flush the latest deferred upload when it settles. Covered by `MetalFramebufferRendererTests`. **Done.**
- [x] T015l [B] Physical iPhone correction: coalesce renderer viewport redraws to display-link cadence instead of calling `MTKView.draw()` directly from every touch callback, let zoomed one-finger pan begin without waiting for long-press failure, and mirror zoom/pan/PiP focus on display-link ticks during the gesture. Covered by focused SwiftPM tests and full app build verification. **Done.**
- [x] T015m [B] Physical iPhone correction: keep direct pinch, zoomed pan, and pan-deceleration SwiftUI/PiP mirroring deferred until the gesture settles; keep a latest-frame flush pending when gesture-time redraw throttling skips GPU uploads; and guard Compose's UIKit editor from external draft sync while iOS marked text is active. Covered by focused gesture/compose tests, full `swift test`, iOS simulator build, and live Mac VNC connect-path smoke. **Done.**
- [x] T016 [B][VISUAL] Screenshots: trackpad cursor visible, direct mode (no cursor), mode toggle. **Done.** Direct mode/no-cursor is covered by `16-session-active-widescreen-iphone-{light,dark}.png`; trackpad/server-cursor overlay is covered by `18-session-active-trackpad-cursor-iphone-{light,dark}.png`.

## Stage C — Connection quality + compose quick keys
- [x] T020 [P][C] `ConnectionQuality` + `ConnectionQualityEstimator` in Core. **Done.**
- [x] T021 [P][C] `ConnectionQualityTests.swift` — 7 tests (bucket thresholds, EMA, reset, unknown-on-empty). **Done.**
- [x] T022 [C] Latency sampled in the stream loop → `@Published connectionQuality` on the model, reset on connect/disconnect/profile-change, surfaced in the live control overlay. **Done.**
- [x] T023 [C] Inline Compose quick-key strip (Esc/Tab/⌃C/↑/↓) in `RemoteInputDockView`, dispatch via `model.sendComposeQuickKey`, draft untouched, gated on active session. `ComposeQuickKeyTests` (7) + `ComposeQuickKeyModelTests` (2). **Done.**
- [x] T023a [C] Compose paste stabilization: macOS Command-V uses the common Mac VNC `Alt_L` mapping and the production app waits briefly after remote clipboard set before paste. **Done.**
- [x] T024 [C][VISUAL] Quality chip and compact quick-key menu covered by the active-session UX-audit captures (`16-*` and `17-*`). **Done.**

## Cross-cutting
- [~] T030 Re-capture the UX-audit screenshot set; active-session light/dark + keyboard captures refreshed for this PR. Full UX-audit set still pending a broader pass.
- [ ] T031 Update `ROADMAP.md` (new "Phase 11 — Session Experience" or extend Phase 5/6 notes) + `PRODUCT_SPEC.md §6.2` to reflect shipped pointer modes / zoom-pan / screen-first viewport.
- [ ] T032 [Manual] Real Mac VNC trackpad + zoom-to-read on physical iPhone — BLOCKED (no device); record residual risk per constitution §III.
- [ ] T033 [Manual] Physical iPhone Korean/CJK Compose IME retest — verify marked-text composition in the compact `UITextView` dock and record iOS version, keyboard, target app, and whether the sent remote paste matches the local draft exactly.

## Dependencies
Stage A core (T001/T002) → A app (T003–T006). Stage B core (T010–T013) parallel with A app; B app (T014–T016) needs A app + B core. Stage C is independent of B and can overlap. VISUAL tasks wait on their stage's app tasks.
