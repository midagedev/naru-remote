# Tasks: Adaptive Server-Side Downscale (Apple ScaleFactor)

- [x] **T001** Core policy `AppleServerDownscalePolicy`: Apple gate, lossless
      ladder {1.0, 0.5}, 10-tick hysteresis, instant upscale on zoom, mid-resize
      hold + counter reset, no-repeat-rung, `reset()`. File:
      `NaruRemote/Sources/NaruRemoteCore/SessionViewer/AppleServerDownscalePolicy.swift`.
- [x] **T002** Core decision-table tests (every FR-001..FR-004 row, both
      lossless-boundary sides, 9-vs-10 hysteresis, zoom, hold, gate-off). File:
      `NaruRemote/Tests/NaruRemoteCoreTests/AppleServerDownscalePolicyTests.swift`.
- [x] **T003** Boundary protocol `RFBServerScalingClient` (optional downcast,
      not folded into `RFBStreamingClient`) plus `RFBNetworkClient` handshake
      recording of advertised Apple security types 30/33/35/36. Files:
      `RFBClientBoundary.swift`, `RFBNetworkClient.swift`.
- [x] **T004** FAIL-first model tests against the unmodified app model, then
      wiring: evaluate on each incremental tick next to
      `currentViewportRequestRegion`, send ScaleFactor through the boundary,
      reset at transform-nil and streamID bump. Files:
      `NaruRemoteAppModel.swift`, `NaruRemoteAppModelTests.swift`.
- [x] **T005** View plumb: `@Environment(\.displayScale)` forwarded via
      `onViewportDisplayPixelScaleChange` / `updateViewportDisplayPixelScale`.
      File: `SessionViewportView.swift`. AppShell wiring is outside this
      whitelist — production falls back to assumed ppp 3 until the lead
      connects the callback.
- [x] **T006** `swift test` for the new Core + App model cases.

Follow-on (lead-owned, residual):

- [x] **T007** Wire `onViewportDisplayPixelScaleChange` in
      `NaruRemoteAppShell.swift` to `model.updateViewportDisplayPixelScale`
      (lead, 2026-08-20; iPhone simulator build green after
      `xcodegen generate`).
- [x] **T007b** Lead review found a spec-authored defect: the FR-002
      lossless condition re-read against the post-resize transform flapped
      the ladder 0.5↔1.0. Fixed by rung normalization
      (`displayScale × appliedRung × ppp ≤ 0.5`), FAIL-first in
      `testStaysDownscaledAfterServerResizeAppliesTheHalfFramebuffer`;
      the boundary test's second half was re-authored to the corrected
      contract (attribution in-file). Full `swift test` from cold: 1634
      tests, 0 failures.
- [x] **T008** Live pointer-mapping check while scaled (lead, 2026-08-20):
      **the server does NOT inverse-map** — scaled coordinates landed at
      half the physical center; full-framebuffer coordinates landed with
      0.0pt error. Gated in
      `LiveMacPointerHoverTests/testScaledSessionPointerInputSpaceStaysUnscaled`
      (fails if a macOS update ever starts inverse-mapping, which would
      make our client-side multiplier double-map).
- [x] **T008b** Client-side pointer mapping (lead, FR-008): pure
      half-shape detector `AppleServerDownscalePolicy.pointerCoordinateMapping`
      + single choke point in `enqueuePointerCommands`; unscaled baseline
      captured when the 0.5 request is sent. FAIL-first: tap while scaled
      sent (30,30) before the fix, (60,60) after
      (`testPointerCoordinatesMapToUnscaledSpaceWhileDownscaled`).
- [~] **T009** Founder device pass (sharpness at fit + zoom round-trip).
