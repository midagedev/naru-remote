# Implementation Plan: VNC-First, Helper-Optional Presentation

**Feature**: `specs/042-vnc-first-helper-optional/spec.md`
**Created**: 2026-09-07
**Status**: Active

## Summary

No new transport, no new protocol version. This feature changes what the
phone *says* and makes helper video *behave* like VNC: entry surfaces put
manual VNC first (P1/P4), the session shows transport only when helper
video is live and announces a fallback once with a catalog reason (P2/P3),
the helper stops baking the Mac pointer into frames when the phone is in
trackpad mode (P5), pinch/pan parity over the video preview is restored
(P5), the RFB client stops requesting framebuffer updates while video is
live (P5), and a profile can be pinned to VNC (P6).

## Architecture

### Where each principle lands

| Principle | Layer | Files | Round |
| --- | --- | --- | --- |
| P1/P4 entry hierarchy and copy | `NaruRemoteApp` views | `Features/Home/EmptyHomeView.swift`, `Features/ConnectionHub/ConnectionGridView.swift`, `Features/ConnectionHub/NaruPairingFlowView.swift`, `UITests/*` | A |
| P2/P3 transport marker + fallback notice | `NaruRemoteApp` model/snapshot/view | `AppShell/NaruRemoteAppModel.swift`, `AppShell/NaruRemoteAppSnapshot.swift`, `AppShell/NaruRemoteAppShell.swift`, `Features/SessionViewer/SessionViewportView.swift` | B |
| P5 one cursor (wire + helper) | `NaruRemoteCore/HelperVideo` + `NaruHelperKit` | `HelperVideoTransport.swift` (request body field), Kit request handler + ScreenCaptureKit source | C |
| P5 pinch parity — root cause | tests only in the first round | new XCTest/XCUITest reproducing the dead pinch over the helper-video preview | E-inv |
| P5 pinch parity — fix; P5 framebuffer gating; P6 transport pin; phone → helper pointer mode | `NaruRemoteApp`, `NaruRemoteCore/ConnectionHub` | `SessionViewportView.swift`, `MetalFramebufferView.swift`, `NaruRemoteAppModel.swift`, `ConnectionProfile.swift`, `ProfileEditorView.swift` | D (after B, C, E-inv) |

### Decisions

1. **Marker and notice are catalog values.** `VisualTransportMode` already
   exists on the snapshot (`.vncFramebuffer` / `.helperVideo`). The view
   renders a marker for `.helperVideo` only. The fallback notice reason is
   derived from `HelperVideoFailureCode` through a fixed mapping in the
   snapshot layer (the same shape as `helperVideoAvailability(for:)` in
   the model); no free text, no address, no error string (constitution
   §IV). "Once per session" is a latch keyed on `sessionID`, cleared with
   `resetVisualTransportState()`.
2. **Notice only when video was expected.** The latch arms only when the
   profile's `helperVideo?.isEnabled == true` and not revoked, and the
   transport preference (D) is `.automatic`. A VNC-only profile never sees
   a marker or a notice (P2).
3. **Pointer mode rides the start request.** `HelperVideoStartStreamRequestBody`
   gains an optional `pointerMode: HelperVideoPointerMode?` (`trackpad` /
   `directTouch`); absent ⇒ helper behaves as today (`showsCursor = true`).
   Old phones and old helpers keep interoperating: the field is optional
   on both sides and `Codable` decode uses `decodeIfPresent`. The helper
   maps `trackpad` ⇒ `SCStreamConfiguration.showsCursor = false`. Mode
   changes mid-session: research R1 decides between
   `SCStream.updateConfiguration` and a restart; the Kit exposes one
   method either way.
4. **Framebuffer gating lives in the pump.** The pump loop in
   `NaruRemoteAppModel` already consults
   `isHelperVideoHealthyPrimaryVisualTransport` for pacing. FR-008 turns
   that into "do not issue the next `FramebufferUpdateRequest` while true;
   resume with a full (non-incremental) request on fallback". The RFB
   connection stays open. Tested with `FakeRFBServerKit` by counting
   update requests per transport state.
5. **Transport preference is a profile field with a safe default.**
   `HelperVideoConnectionConfiguration` gains
   `transportPreference: HelperVideoTransportPreference` (`automatic` /
   `vncOnly`), `decodeIfPresent ?? .automatic` so every stored profile
   loads unchanged. The editor shows it only when a helper pairing exists.
6. **Manual entry from the scanner is a callback.** `NaruPairingFlowView`
   gets `onEnterManually: (() -> Void)? = nil`; Round A adds the button
   and parameter, the lead wires it in `NaruRemoteAppShell` after B lands
   (the shell is B's file), so A and B never write the same file.
7. **Pinch parity is investigated before it is fixed.** The founder's
   report ("줌인 같은 기본적인 제스쳐도 안되네") is a symptom; the code
   path (`sampleBufferLayerPreview` → `sampleBufferHotInputOverlay` →
   `MetalFramebufferInputOverlayView`) looks shared with VNC. E-inv writes
   a failing test first (or proves the path works and names what differs
   on the founder's device); D fixes against that test.

### Research (`research.md`)

- **R1** `SCStream.updateConfiguration(_:)` on macOS 14: does toggling
  `showsCursor` apply live, and does it force a keyframe? Decides decision 3.
- **R2** Why pinch is dead over the helper-video preview on device. E-inv
  round; outcome recorded in `research.md`.
- **R3** Screen Sharing behaviour when a client stops requesting updates for
  minutes and then sends a full request: does it resend the whole frame
  promptly? Verified against the live Mac by the D round (FakeRFBServer
  for the unit gate, live Mac for the behaviour).

## Verification matrix (iPhone first)

| Gate | Command | Covers |
| --- | --- | --- |
| SwiftPM | `swift test` (full) | Core codable defaults, snapshot mapping, Kit `showsCursor` policy, pump gating with `FakeRFBServerKit` |
| App unit | `swift test --filter NaruRemoteAppTests` | notice latch once-per-session, marker state, preference gating |
| iPhone UI | `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/VncFirstScreenshotsUITests` | entry hierarchy screenshots under `artifacts/screenshots/vnc-first/` (opus vision verdict, not GLM) |
| Kit | `swift test --filter NaruHelperKitTests` | request body decode, configuration policy |
| Device | founder pass | one cursor, pinch, bandwidth (`nettop` on the Mac) |

## Risks

- `NaruRemoteAppModel.swift` is ~9,500 lines and is touched by B and D;
  they run sequentially, never in parallel.
- The helper wire change is additive; a mismatched phone/helper pair
  degrades to today's behaviour (two cursors), never to a refused start.
- Copy changes touch strings that spec 040's UI tests assert on
  (`QrPairingScreenshotsUITests`); Round A owns that test file and updates
  the assertions with the copy.
