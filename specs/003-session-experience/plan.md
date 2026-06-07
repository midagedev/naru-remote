# Implementation Plan: Session Experience — GRD-Class Viewport & Pointer Control

**Feature**: `003-session-experience` · **Product**: Naru Remote · **Created**: 2026-05-31

## Architecture

Pressure flows from constitution §VI (iPhone-first) and §I (zoom/pan/cursor are LOCAL transforms — no RFB messages). The split keeps all geometry/decision logic pure in `NaruRemoteCore` (so it is `swift test`-able with no simulator) and confines UIKit/SwiftUI to the App layer.

- **`NaruRemoteCore/SessionViewer/`** (pure, no UIKit):
  - `ViewportTransform` — aspect-fit × zoom × pan mapping, view↔framebuffer, pan clamping, zoom-about-anchor. Single source of truth for both pointer modes (FR-014).
  - `TrackpadCursor` — framebuffer-pixel cursor with relative move + clamp + visibility.
  - `PointerControlMode` — `directTouch | trackpad` enum + product default.
  - `ConnectionQuality` + `ConnectionQualityEstimator` — coarse bucket from an EMA of frame round-trip latency (no value retained/logged).
  - `PointerGestureResolver` — pure: `(mode, gesture, transform, cursor) → (cursor', transform', [RFBPointerCommand])`. The App model executes the commands via the existing `RFBPointerEventClient`.
- **`NaruRemoteApp/Features/SessionViewer/`** (SwiftUI/UIKit):
  - Rewrite `SessionViewportView` to be **screen-first**: framebuffer at the server's true aspect ratio filling the session area; controls move to a compact `SessionControlBar` overlay; diagnostics move behind a disclosure/sheet.
  - Extend `MetalFramebufferHostingView` gestures: 1-finger pan (direct, when zoomed), double-tap zoom, trackpad cursor-move/tap/2-finger-tap/tap-and-a-half; report through new closures.
  - `TrackpadCursorView` overlay; `SessionControlBar` (disconnect / pointer-mode / keyboard / zoom-reset / status chip + quality).
  - Inline Compose quick-key strip (Esc/Tab/Ctrl-C) in `RemoteInputDockView`, dispatching via the existing `model.tapDirectKey`-style path / `KeystrokeEmitter`.
- **`NaruRemoteApp/AppShell/NaruRemoteAppModel`**: owns `pointerControlMode`, `trackpadCursor`, `viewportTransform`-relevant state, `connectionQuality`; routes gestures through `PointerGestureResolver` and dispatches commands; samples frame round-trip latency in the stream loop. All new state resets on disconnect / profile change / fresh connect (mirrors the Direct-mode reset discipline).

Dependency rule preserved: `iOSApp → NaruRemoteApp → NaruRemoteCore`; Core gains only `CoreGraphics`/`Foundation` (no UIKit).

## Adapters / boundaries

One optional RFB input boundary is added for latest-value cursor latency, not
new protocol semantics: `RFBBestEffortPointerEventClient` can send a single
buttonless (`0x00`) cursor-follow `PointerEvent`. Trackpad still emits
**absolute** `PointerEvent`s (RFC 6143 §7.5.5) from the cursor position;
relativity is local cursor bookkeeping. All RFB user-input writes return after
transport enqueue rather than waiting for Network.framework
`contentProcessed`; clicks, drags, scroll, and keys preserve ordering through
the app-level pointer/key lanes, not through blocking socket completion.
Quick keys reuse `RFBKeyEventClient`/`KeystrokeEmitter`. No clipboard, no
helper, no new credential surface.

## Data flow

Gesture (view points) → `MetalFramebufferHostingView` closure → `NaruRemoteAppModel` → `PointerGestureResolver.resolve(...)` using the current `ViewportTransform` + `TrackpadCursor` → returns updated cursor/transform (published → SwiftUI redraw of overlay/scale) + zero-or-more `RFBPointerCommand` → model dispatches pointer commands via `activePointerClient` on the pointer outbound lane (dropped silently if not `.active`). A single buttonless cursor-follow command uses `RFBBestEffortPointerEventClient` when available; multi-command/non-zero-mask pointer gestures use the ordered pointer lane but still enqueue to the transport without waiting for `contentProcessed`. Direct-mode and Compose quick-key `KeyEvent`s dispatch through a separate key outbound lane, so bursty trackpad-move writes cannot park keyboard input behind a pointer backlog. Pointer-lane timeouts clear only the lane backlog, not the session's pointer capability or coordinate space, so the next gesture retries. Zoom/pan return commands == `[]` (constitution §I). Frame arrival in the stream loop records a latency sample → `ConnectionQualityEstimator` → published bucket.

## Verification Matrix (constitution §III; iPhone before iPad)

| Layer | Test | Type | Device |
| --- | --- | --- | --- |
| `ViewportTransform` | fit-scale, view↔fb round-trip, pan clamp, zoom-about-anchor, letterbox→nil | Unit (`swift test`) | iPhone sim |
| `TrackpadCursor` | relative move scaled by displayScale, clamp to bounds, centered() | Unit | iPhone sim |
| `ConnectionQuality(+Estimator)` | bucket thresholds, EMA, reset, unknown on no sample | Unit | iPhone sim |
| `PointerGestureResolver` | direct tap maps through zoom+pan; trackpad tap@cursor; 2-finger@cursor; tap-and-a-half; zoom/pan emit `[]` | Unit + Fake RFB | iPhone sim |
| Model integration | mode/cursor/transform/quality reset on disconnect/profile-change; latency sampling; trackpad-move backlog does not block key lane | XCTest (`NaruRemoteAppTests`) | iPhone sim |
| Screen-first layout, pointer-mode toggle, cursor overlay, quick keys | XCUITest + screenshots (vision-judge) | iPhone 17 Pro / iOS 26.2 | iPhone sim |
| Graceful scaling | screenshots | iPad Pro 13" sim |
| Real Mac VNC trackpad/zoom feel | Manual | iPhone physical — **residual risk** (no device in env), recorded per §III |

UI tasks follow `feedback_ui_iteration_via_simulator_screenshots`: implement → screenshot iPhone sim → Read-tool vision-judge against this spec → iterate.

## Constitution Check

| Principle | How satisfied |
| --- | --- |
| §I Input composed locally | Zoom/pan/cursor are local transforms (emit no RFB); Compose & Send stays default; quick keys are discrete control keysyms, not a multilingual path |
| §II Tailnet-native | No connection-flow change |
| §III Verification before confidence | Pure Core types are fully unit-tested; UI screenshot-judged; real-server feel marked residual risk |
| §IV Security boundaries | Coordinates/cursor/scroll/keysym/latency never logged or exported; diagnostic safe-catalog unchanged |
| §V Traceable & small | Staged PRs (A: Core+viewport, B: trackpad+cursor, C: quality+quick-keys), disjoint write sets per task |
| §VI Phone-first | Every VISUAL task targets iPhone first; iPad screenshots follow; trackpad+cursor is the phone precision win |

## Staging (PR boundaries)

- **Stage A** — Core `ViewportTransform` (+ tests) and screen-first `SessionViewportView` rewrite: true-aspect full-bleed framebuffer, pinch-zoom with **pan when zoomed** (direct mode), double-tap zoom, compact `SessionControlBar`, diagnostics behind disclosure. Existing tap/long-press/scroll preserved through the shared transform.
- **Stage B** — `TrackpadCursor` + `PointerControlMode` + `PointerGestureResolver` (+ tests); cursor overlay; trackpad gestures (move/tap/2-finger-tap/tap-and-a-half); auto-pan-to-cursor; mode toggle in the control bar.
- **Stage C** — `ConnectionQuality`(+Estimator) + status/quality chip; Compose inline quick-key strip (Esc/Tab/Ctrl-C).

## Risks / mitigations

- **Gesture conflicts** (pan vs drag vs scroll vs pinch): resolve by finger count + mode; `require(toFail:)` and simultaneous-recognition rules as today; unit-test the resolver decision table.
- **Real-server fidelity** (frame rate, encodings) is out of scope and gated to `specs/004`; this feature improves perceived usability on whatever frames arrive.
- **Layout regressions** on existing UX-audit screenshots: re-capture the audit set; treat diffs as intentional and document in the PR.
