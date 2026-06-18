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
- [x] T015n [B] Physical iPhone correction: notify the app model while Metal-hosted viewport gestures are active so streaming framebuffer publication is coalesced to the latest pending frame until the gesture settles, and clear the Compose draft after the paste command leaves the device while keeping failed sends retryable. Covered by focused model/core tests. **Done.**
- [x] T015o [B] Physical iPhone correction: smooth zoomed trackpad auto-pan by damping the follow-pan delta instead of snapping the viewport to the cursor reveal margin, reduce the viewport-relative follow zone, and keep one Metal viewport redraw display link alive during active gestures instead of recreating it every frame. Covered by `PointerGestureResolverTests`, `TrackpadModeModelTests`, and app build verification. **Done.**
- [x] T015p [B] Compact Compose correction: make the UIKit `UITextView` expose the active-session editor directly to accessibility/UI tests, and focus it from the full visible editor shell so tapping the compact input box reliably raises the iOS keyboard. Covered by active-session UX-audit focused UI tests. **Done.**
- [x] T015q [B] Physical iPhone correction: treat trackpad cursor movement as a viewport interaction only when the viewport is actually pannable, so unzoomed trackpad moves no longer defer remote frame/server-cursor publication; raise gesture-time incoming-frame redraw pacing from 15fps to 30fps; make zoomed auto-pan catch up faster; and read Compose text directly from the active `UITextView` before send/disable decisions. Covered by focused gesture/compose tests, full `swift test`, synthetic frame benchmark, iPhone simulator build, and active-session UI screenshot tests. **Done.**
- [x] T015r [B] Physical iPhone correction: stop incoming VNC frames from scheduling redundant redraws while the Metal viewport upload path is suspended during local pinch/pan, run viewport/deceleration display links at the device screen maximum for Photos-like local navigation, and recover active IME marked text when `UITextView` briefly reports an empty committed snapshot on Compose Send. Covered by focused compose/gesture tests and iPhone simulator build verification. **Done.**
- [x] T015s [B] Physical iPhone correction: move local pinch/zoomed-pan/deceleration presentation back onto the Core Animation compositor by transforming the embedded `MTKView` layer, remove the touch-time viewport redraw display link, keep the Metal renderer at a stable aspect-fit baseline, and preserve Compose drafts after unconfirmed paste dispatch so failed/missed remote pastes stay retryable. Covered by focused viewport/Compose tests, live Mac VNC smoke, simulator/generic iOS builds, and synthetic frame benchmarks. **Done.**
- [x] T015t [B] Physical iPhone correction: make pinch gestures pan with the two-finger centroid instead of treating centroid drift as inert zoom noise, preserve pannable crop-fill baseline offsets at the minimum zoom floor, and harden Compose `UITextView` snapshot resolution when marked text is present but UIKit briefly reports an incomplete committed string. Covered by `ViewportTransformTests` and `RemoteInputDockSyncPolicyTests`. **Done.**
- [x] T015u [B] Physical iPhone diagnostic follow-up: add safe aggregate gesture-cadence diagnostics (`viewportGestureSampleCount`, long-frame count, max interval bucket) to diagnostic JSON v14, show actionable Compose send status in compact keyboard-accessory mode, and keep the compositor viewport hot path from resetting renderer state on every touch callback. Covered by focused diagnostic/input tests and generic iOS device build verification. **Done.**
- [x] T015v [B] Sustained-session thermal follow-up: detect consecutive content frames that force full renderer uploads and temporarily apply the same 30fps power-saver pacing floor used for Low Power Mode, while keeping localized terminal/IDE dirty-rect updates on the faster active cadence. Mirrored in `VNCLiveBenchmark` client-pressure policy so live reports can predict the app's adaptive pacing. **Done.**
- [x] T015w [B] Physical iPhone correction: allow throttled one-shot framebuffer uploads during active Metal viewport gestures, narrow the zoomed trackpad follow zone so central cursor motion no longer drags the viewport, and suppress Compose draft/model propagation while iOS marked text is active. Covered by focused renderer, gesture, and Compose sync tests. **Done.**
- [x] T015x [B] Physical iPhone correction: mirror direct pinch/zoomed-pan/deceleration state back to SwiftUI/PiP/cursor overlays on a screen-rate display link while keeping the visible Metal transform on the hot path, and read multiple stabilized `UITextView` snapshots after marked-text commit so delayed Korean/CJK IME commits do not lose the final glyph. Covered by focused viewport build verification and Compose stabilization tests. **Done.**
- [x] T015y [B] Physical iPhone correction: return immediate trackpad cursor feedback from the app model to the Metal host, render the server/synthetic cursor on the UIKit hot path, hide the lagging SwiftUI cursor overlay when Metal owns input, and add frame-settled Compose Send reads for delayed Korean/CJK IME commits. Covered by focused trackpad and Compose sync tests. **Done.**
- [x] T015z [B] Physical iPhone correction: prioritize touch tracking during local viewport manipulation by matching the Metal host's gesture-time remote-frame upload throttle to the Core 15fps default, stop propagating Compose draft changes to the model while iOS marked text is active, and explicitly notify the model when UIKit commits marked text so Korean/CJK IME composition stays local until commit but the final draft cannot be missed. Covered by focused gesture/Compose sync tests. **Done.**
- [x] T015aa [B] Physical iPhone correction: make Metal-hosted local viewport gestures fully coalesce incoming framebuffer uploads, including the first gesture-time frame, then flush only the latest deferred frame after the gesture settles so pinch/pan stays on the compositor path without texture-upload hitches. Covered by `ViewportGestureRedrawThrottleTests`. **Done.**
- [x] T015ab [B] Physical iPhone correction: keep late SwiftUI trackpad cursor snapshots from overwriting the Metal/UIKit hot cursor during active drags, mirror gesture-end viewport state back to SwiftUI as one final `ViewportTransform`, and dedupe Compose draft propagation so Korean/CJK marked-text commits do not double-write the model. Covered by focused viewport/Compose policy tests. **Done.**
- [x] T015ac [B] Physical iPhone correction: reduce zoomed trackpad auto-pan step size for tiny high-refresh touch samples while preserving large follow movement, and preserve full Compose text when UIKit briefly reports an empty or missing committed snapshot during marked-text send. Covered by `PointerGestureResolverTests`, `RemoteInputDockSyncPolicyTests`, and `TrackpadModeModelTests`. **Done.**
- [x] T015ad [B] Physical iPhone correction: raise the tiny-sample zoomed trackpad auto-pan catch-up floor so the viewport follows the cursor without single-digit stepped lag, and widen Compose Send's IME stabilization window so delayed Korean/CJK commits can settle before clipboard/paste dispatch. Covered by `PointerGestureResolverTests` and `RemoteInputDockSyncPolicyTests`. **Done.**
- [x] T015ae [B] Physical iPhone correction: make zoomed trackpad movement pan continuously with the cursor instead of waiting for the reveal edge, reduce pointer-move/cursor publish coalescing to an 8 ms frame window for high-refresh devices, and keep the longest stabilized Compose snapshot when iOS IME briefly returns a fragment before Send. Covered by `PointerGestureResolverTests`, `TrackpadModeModelTests`, and `RemoteInputDockSyncPolicyTests`. **Done.**
- [x] T015af [B] Physical iPhone correction: keep Metal viewport movement immediate but defer SwiftUI/PiP transform mirroring until gesture end again after physical feedback showed display-link state publication still felt choppy; reject Korean/CJK/emoji Compose on unconfirmed VNC clipboard sessions instead of reporting a false paste success. Covered by focused viewport, app-model, and text-injection tests. **Done.**
- [x] T015ag [B] Physical iPhone correction: make zoomed trackpad cursor travel remain finger-paced while local follow-pan is coupled in, and reduce tiny-sample edge-follow pan caps so high-refresh drags do not step in large chunks near the viewport edge. Covered by `PointerGestureResolverTests`. **Done.**
- [x] T015ah [B] Physical iPhone correction: raise zoomed trackpad follow-pan coupling so the viewport follows the real cursor more continuously while preserving finger-paced visible cursor travel. Covered by `PointerGestureResolverTests` and `TrackpadModeModelTests`. **Done.**
- [x] T015ai [B] Physical iPhone correction: re-apply trackpad stream-continuity gating so fit-scale cursor movement does not claim viewport interaction, suspend Metal uploads, or pause framebuffer requests; only pannable trackpad drags coalesce streamed frames while the local viewport is actually moving. Covered by `SessionViewportViewGeometryTests`, `TrackpadModeModelTests`, and `PointerGestureResolverTests`. **Done.**
- [x] T015aj [B] Compose reliability correction: reject Korean/CJK/emoji Compose payloads when VNC UTF-8 clipboard support is unconfirmed and no reachable helper bridge is available, instead of sending best-effort legacy clipboard data that can look successful while failing remotely. Covered by `TextInjectionAdapterTests` and `NaruRemoteAppModelTests`. **Done.**
- [x] T015ak [B] Physical iPhone correction: keep remote frame requests and framebuffer publication alive during local viewport gestures at a bounded 15fps cadence, instead of pausing requests and deferring every content frame until gesture end. Covered by `ViewportGestureRedrawThrottleTests` and focused app-model stream-pacing tests. **Done.**
- [x] T015al [B] Physical iPhone correction: keep the remote frame request loop alive during local pinch/pan, but defer `latestFramebuffer` publication to one newest pending frame until the gesture settles so SwiftUI/Metal uploads do not compete with the compositor touch path. Covered by focused app-model stream-pacing tests. **Done.**
- [x] T015am [B] Physical iPhone correction: after device feedback still reported unnatural zoom/pan and broken Compose, lower zoomed trackpad pan coupling so the cursor remains finger-paced without over-dragging the viewport, reduce viewport-interaction stream cadence to a conservative 4 Hz floor, and restore strict unconfirmed UTF-8 Compose failure when no helper bridge is reachable. Covered by `PointerGestureResolverTests`, `TrackpadModeModelTests`, `ViewportGestureRedrawThrottleTests`, `TextInjectionAdapterTests`, and focused app-model Compose tests. **Done.**
- [x] T015an [B] Physical iPhone correction: add a trace-level smoothness invariant for zoomed trackpad edge auto-pan so tiny high-refresh drag samples can keep revealing the viewport without making the visible cursor travel backward against the finger. Covered by `PointerGestureResolverTests`. **Done.**
- [x] T015ao [B] Compose diagnostic correction: expose pre-send route fields for local Compose diagnostics so physical iPhone reports can show UTF-8 payload class, planned path, active UTF-8 clipboard support, and fixed route blocker without raw draft text. Covered by `DiagnosticExportTests` and focused `NaruRemoteAppModelTests`. **Done.**
- [x] T015ap [B] Physical iPhone correction: after live device feedback still reported choppy zoom/pan and broken-feeling Compose, reduce central zoomed-trackpad follow-pan coupling so the viewport follows without over-dragging, lower trackpad pointer/cursor coalescing latency, skip the long Compose-send stabilization window when no iOS marked text is active, and compact blocked multilingual Compose failures into one actionable dock line. Covered by `PointerGestureResolverTests`, `TrackpadModeModelTests`, `RemoteInputDockSyncPolicyTests`, and `NaruRemoteAppSnapshotTests`. **Done.**
- [x] T015aq [B] Physical iPhone correction: allow ProMotion-class frame timing on iPhone, keep full-frame VNC uploads coalesced during local viewport gestures, and let small dirty-rect updates publish/request at a bounded 15 Hz cadence so remote cursor/text echo no longer freezes until pinch/pan ends. Covered by focused app-model, redraw-throttle, renderer, simulator benchmark, and iPhone simulator build verification. **Done.**
- [x] T015ar [B] Physical iPhone correction: align the Metal host's gesture-time redraw gate with the 15 Hz dirty-rect promotion cadence so localized remote cursor/text echo can actually reach the renderer during pinch/pan while full-frame uploads remain on the conservative 4 Hz floor. Covered by `ViewportGestureRedrawThrottleTests` and focused app-model stream-pacing tests. **Done.**
- [x] T015as [B] Physical iPhone correction: keep viewport-interaction stream publication idempotent when active signals repeat, and allow full-frame-only VNC servers to publish bounded 4 Hz refresh slots during long pinch/pan gestures instead of freezing until gesture end. Covered by focused app-model stream-pacing tests. **Done.**
- [x] T015at [B] Physical iPhone correction: split viewport-interaction frame policy by gesture kind so direct pinch/pan/deceleration defers framebuffer publication/uploads until gesture end for Photos-like local navigation, while zoomed trackpad cursor-follow keeps bounded live dirty-rect refresh. Compact Compose blocker copy now names Mac helper setup instead of sounding like a broken text field. Covered by focused app-model and dock snapshot/sync-policy tests. **Done.**
- [x] T015au [B] Interaction baseline correction: keep the proven Metal gesture boundary (visible movement on the UIKit/Core Animation hot path, SwiftUI/PiP mirroring deferred until settle), document the larger iPhone interaction goal, and keep Compose Send in the bounded stabilization window after a recent marked-text commit even when UIKit has already cleared `markedTextRange`. Covered by `RemoteInputDockSyncPolicyTests`; physical iPhone retest remains T032/T033. **Done.**
- [x] T015av [B] Physical iPhone follow-up: raise the zoomed trackpad follow-pan coupling again so the viewport follows the real cursor more closely during central drags, while preserving finger-paced visible cursor travel and existing tiny-sample no-snap guards. Covered by `PointerGestureResolverTests` and `TrackpadModeModelTests`. **Done.**
- [x] T015aw [B] Physical iPhone freeze correction: stage incoming framebuffer pixels into a Metal buffer off the MainActor, then let the main draw callback perform only a short blit + present pass so first-frame/full-frame uploads do not monopolize touch tracking or the keyboard. Covered by `MetalFramebufferRendererTests`, focused frame-store/cursor tests, and iPhone simulator build verification. **Done.**
- [x] T015ax [B] Physical iPhone Compose freeze correction: keep the focused compact Compose `UITextView` render identity isolated from model-mirrored draft/helper-status changes while active-session framebuffer churn continues, so the first Korean syllable cannot invalidate the UIKit editor before the second syllable is entered. Send-result status is carried outside the hot editor identity in the follow-up T015bb path. Covered by `RemoteInputDockRenderStateTests` and active-session compact Compose XCUITest on iPhone 17 Pro simulator. **Done.**
- [x] T015ay [B] Trackpad hot-cursor correction: make the Metal host's current visible cursor the source for the next trackpad resolver sample/click before the app model's coalesced published cursor mirror flushes, and cap zoomed edge-follow reveal below half the touch delta so phone-portrait wide-desktop samples keep visible cursor travel in phase with the finger. Covered by `TrackpadModeModelTests`, `PointerGestureResolverTests`, and `2026-06-07-trackpad-hot-cursor-summary.md`. **Done.**
- [x] T015az [B] Physical iPhone input-lane correction: split outbound pointer and key dispatchers so bursty buttonless trackpad-move writes cannot queue Direct-mode keys or Compose quick keys behind pointer backlog, and pointer timeouts no longer cancel the keyboard lane. Covered by `DirectKeystrokeModeTests`, pointer/trackpad model tests, and the live transport-cadence drilldown artifact. **Done.**
- [x] T015ba [B] Physical iPhone input-lane correction: add a `RFBBestEffortPointerEventClient` fast path for single buttonless trackpad cursor-follow moves so the app does not wait for socket `contentProcessed` on lossy/latest-value cursor samples; keep clicks, drags, scroll, and keys on reliable ordered writes. Covered by `DirectKeystrokeModeTests` and `FakeRFBServerIntegrationTests`. **Done.**
- [x] T015bb [B] Physical iPhone Compose correction: keep the focused
  Compose status sibling mounted while UIKit owns the editor so clearing a
  previous `Remote app confirmation unavailable` result after the first
  Korean/CJK syllable cannot collapse the keyboard safe-area stack. Covered by
  `RemoteInputDockRenderStateTests` and the active-session confirmation-clear
  Compose XCUITest on iPhone 17 Pro simulator. **Done.**
- [x] T015bc [B] Compose delivery correction: prefer a reachable helper text
  bridge for every non-empty Compose payload, not only UTF-8 payloads that VNC
  cannot safely clipboard. VNC clipboard + paste remains a fallback when helper
  is absent or not known reachable, so `Remote app confirmation unavailable`
  is no longer the primary result once helper insertion is ready. Covered by
  `NaruRemoteAppModelTests/testModelPrefersReachableHelperForComposePayloadsEvenWhenVNCPasteCouldRun`.
  **Done.**
- [x] T015bd [B] Physical iPhone freeze correction: move continuous trackpad
  cursor mirror publication out of the app model's `@Published` shell state and
  into a viewport-local `TrackpadCursorStore`, then add a deterministic
  active-session cursor-storm XCUITest proving focused compact Compose still
  accepts the second Korean/CJK input step while the viewport cursor mirror is
  under pressure. Covered by `TrackpadModeModelTests` and
  `ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm`.
  **Done.**
- [x] T015be [B] Interaction isolation gate: add deterministic unit coverage
  that a same-size steady-frame flood coalesces to the latest display-cadence
  `SessionFrameStore` event, and that locally composed draft text survives an
  active streaming frame flood. This keeps future renderer/helper-video work
  from regressing into keyboard or Compose state loss while physical iPhone
  retest remains pending. Covered by `SessionFrameStoreTests` and focused
  `NaruRemoteAppModelTests`. **Done.**
- [x] T015bf [B] Interaction reproduction gate: add an iPhone XCUITest fixture
  that combines an active session, stale Compose confirmation status,
  continuous trackpad cursor pressure, and full-frame `SessionFrameStore`
  flood while entering Korean text. This turns the physical "first syllable
  then keyboard freezes" report into a simulator regression gate before the
  helper-video renderer work increases frame pressure again. Covered by
  `ComposeInputResponsivenessUITests`. **Done.**
- [x] T015bg [B] Interaction architecture gate: freeze focused Compose sibling
  chrome while UIKit owns the active IME transaction, and add an iPhone
  XCUITest fixture that combines active-session Compose, stale confirmation
  status, trackpad cursor pressure, full-frame framebuffer flood, and
  app-model `@Published` chrome churn while entering Korean text. This
  reproduces the broader live-session freeze class instead of only the
  framebuffer/cursor subset. Covered by `RemoteInputDockRenderStateTests` and
  `ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFullInteractionStorm`.
  **Done.**
- [x] T015bh [B] Interaction architecture correction: move active-session
  send/helper status out of the equatable Compose editor host, remove
  non-leaf SwiftUI accessibility identifiers that clobbered the real
  `UITextView`/button identifiers, and add a lifecycle-probed iPhone XCUITest
  proving the same focused `UITextView` instance (`make=1`, stable token,
  first responder) survives trackpad cursor pressure, full-frame framebuffer
  flood, and app-model chrome churn while entering multi-step Korean text.
  Covered by `RemoteInputDockRenderStateTests`,
  `RemoteInputDockSyncPolicyTests`,
  `ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeKeepsEditorInstanceDuringFullInteractionStorm`,
  `ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFullInteractionStorm`,
  and `DirectKeystrokeFR010UITests/testDockBadgeAppearsOnDirectAndDisappearsOnCompose`.
  **Done.**
- [x] T015bi [B] Interaction architecture gate: extend the focused Compose
  full-interaction storm with helper-video health churn so the simulator
  reproduces the class where a live visual transport starts publishing
  renderer/status pressure while the iOS IME owns the compact `UITextView`.
  The gate keeps the same editor instance (`make=1`, stable token, first
  responder) alive through two Korean input steps while framebuffer flood,
  trackpad cursor pressure, app-model chrome churn, and helper-video health
  updates all run. Covered by
  `ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeSurvivesHelperVideoHealthStorm`.
  **Done.**
- [x] T015bj [B] Physical iPhone input-lane correction: reproduce the
  post-connect gesture freeze where a stalled pointer write permanently disables
  later pointer input, keep pointer capability/coordinate space alive after
  lane timeouts, and make production RFB `PointerEvent`/`KeyEvent` writes return
  after transport enqueue instead of waiting for Network.framework
  `contentProcessed`. Covered by
  `DirectKeystrokeModeTests/testTimedOutPointerInputDoesNotPermanentlyDisableLaterPointerInput`,
  `DirectKeystrokeModeTests`, `TrackpadModeModelTests`, and
  `PointerEventTapTests`. **Done.**
- [x] T015bk [B] Physical iPhone Compose correction: reproduce the whole-suite
  race where editing a Compose draft during the VNC clipboard settle window left
  the old injection attempt timing-dependent, and cancel the pending paste
  command when the draft identity changes so stale text cannot be pasted after
  the user has started a new Korean/CJK draft. Covered by
  `NaruRemoteAppModelTests/testEditingComposeDraftDuringSendCancelsStalePasteCommand`,
  focused `NaruRemoteAppModelTests`, and full `swift test`. **Done.**
- [x] T015bl [B] Compact live-session chrome correction: collapse the
  Mission/App Windows/Switch App Mac control strip into a one-tap menu inside
  the compact accessory dock so active sessions recover vertical screen space
  while keeping the controls reachable. Covered by
  `RemoteInputDockRenderStateTests`, active-session UX-audit assertions, and
  iPhone simulator build verification; the focused XCUITest launch path timed
  out in simulator install/launch and needs a later screenshot rerun. **Done.**
- [x] T015bm [B] Compact live-session chrome correction: collapse secondary
  immersive control-bar actions (Checks, stream pacing, PiP Watch, and
  pre-connect stream experiments) into a one-tap `Session tools` menu while
  keeping status, Disconnect, and pointer-mode toggle as primary controls.
  Covered by active-session UX-audit assertions and focused iPhone simulator
  build verification. **Done.**
- [x] T015bn [B] Profile-detail chrome correction: keep pre-connect iPhone
  actions focused on Checks, Connect, and status while moving stream tuning,
  startup experiments, and PiP Watch into the same one-tap `Session tools`
  menu; hide the disabled pointer-mode toggle until a session is active.
  Covered by profile-detail UX-audit assertions, focused app tests, and
  iPhone simulator build verification. **Done.**
- [x] T016 [B][VISUAL] Screenshots: trackpad cursor visible, direct mode (no cursor), mode toggle. **Done.** Direct mode/no-cursor is covered by `16-session-active-widescreen-iphone-{light,dark}.png`; trackpad/server-cursor overlay is covered by `18-session-active-trackpad-cursor-iphone-{light,dark}.png`.

## Stage C — Connection quality + compose quick keys
- [x] T020 [P][C] `ConnectionQuality` + `ConnectionQualityEstimator` in Core. **Done.**
- [x] T021 [P][C] `ConnectionQualityTests.swift` — 7 tests (bucket thresholds, EMA, reset, unknown-on-empty). **Done.**
- [x] T022 [C] Latency sampled in the stream loop → `@Published connectionQuality` on the model, reset on connect/disconnect/profile-change, surfaced in the live control overlay. **Done.**
- [x] T023 [C] Inline Compose quick-key strip (Esc/Tab/⌃C/↑/↓) in `RemoteInputDockView`, dispatch via `model.sendComposeQuickKey`, draft untouched, gated on active session. `ComposeQuickKeyTests` (7) + `ComposeQuickKeyModelTests` (2). **Done.**
- [x] T023a [C] Compose paste stabilization: macOS Command-V uses the documented VNC Mac `Alt_L` mapping, and the production app waits briefly after remote clipboard set before paste. **Done.**
- [x] T024 [C][VISUAL] Quality chip and compact quick-key menu covered by the active-session UX-audit captures (`16-*` and `17-*`). **Done.**
- [x] T025 [C][VISUAL] Compact live-session Compose now hides the empty,
  unfocused editor behind a 40pt Compose affordance, expanding back to the
  88pt editing surface when tapped, focused, or when a draft exists so remote
  screen space stays dominant without destabilizing Korean/CJK IME
  transactions. Covered by `RemoteInputDockRenderStateTests` and the
  active-session UX-audit flow; MCP fallback evidence lives in
  `artifacts/screenshots/ux-audit-compact-idle/`. **Done.**

## Cross-cutting
- [~] T030 Re-capture the UX-audit screenshot set; active-session light/dark +
  keyboard captures refreshed for this PR. The iPad audit loop now also covers
  active widescreen, keyboard-expanded Compose, and trackpad cursor states in
  portrait/landscape light/dark. Full UX-audit set still pending a broader pass.
  The screenshot harness accepts `NARU_UX_AUDIT_OUTPUT_DIR` for worktree-local
  iPhone/iPad evidence.
- [x] T031 Update `ROADMAP.md` (extend Phase 5 notes) + `PRODUCT_SPEC.md §6.2` to reflect shipped pointer modes / zoom-pan / screen-first viewport and compact live-session Dock behavior. **Done.**
- [ ] T032 [Manual] Real Mac VNC trackpad + zoom-to-read on physical iPhone — BLOCKED (no device); record residual risk per constitution §III.
- [ ] T033 [Manual] Physical iPhone Korean/CJK Compose IME retest — verify marked-text composition in the compact `UITextView` dock and record iOS version, keyboard, target app, and whether the sent remote paste matches the local draft exactly.
- [x] T034 [Cross-cutting] Physical sustained interaction gate verdict: add
  `physicalGateVerdict` to diagnostic schema v29 so the 10 minute iPhone gate has
  a strict production-promotion signal (`pass` only with no sustained-session
  issue codes; otherwise `blocked`) while preserving the existing detailed
  warning/fail triage. Covered by `DiagnosticExportTests` and
  `NaruRemoteAppModelTests`. **Done.**

## Dependencies
Stage A core (T001/T002) → A app (T003–T006). Stage B core (T010–T013) parallel with A app; B app (T014–T016) needs A app + B core. Stage C is independent of B and can overlap. VISUAL tasks wait on their stage's app tasks.
