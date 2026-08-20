# Tasks: Network-Constrained Stream Caps (Low Data Mode)

- [x] **T001** Core conditions value. Create file
      `NetworkPathConditions.swift` inside
      `NaruRemote/Sources/NaruRemoteCore/SessionViewer/`.
- [x] **T002** Live monitor. Create file
      `NetworkPathConditionsMonitor.swift` inside
      `NaruRemote/App/AppShell/` (NWPathMonitor snapshot wrapper,
      handler-testable) + unit test.
- [x] **T003** Helper lane cap: `isNetworkConstrained` input on
      `HelperVideoStartRequestPolicy` (**FAIL-first** policy test), wired
      from the model's `helperVideoStartRequestBody()`.
- [x] **T004** VNC lane cap: constrained joins powerSaver/LowPower in
      `configuredSustainedEncodingPreference()` and
      `initialStreamPixelFormatPreference()` (**FAIL-first** via the
      `renegotiatedPreferences` seam) + the expensive-only no-change guard
      test. Files: `NaruRemoteAppModel.swift`,
      `NaruRemoteAppModelTests.swift`.
- [x] **T005** Model DI: `networkPathConditionsProvider` init parameter,
      default wired to the shared monitor.
- [x] **T006** Lead review (2026-08-20): diff read in full — model diff
      confined to the DI block and the three named functions; existing
      assertions unchanged (only the new parameter added with false);
      RGB565 pairing and the §VI expensive-only guard both pinned by test.
      `swift test` from cold: 1668 tests, 0 failures. `xcodegen generate`
      + iPhone 17 Pro simulator build green. Committed.
