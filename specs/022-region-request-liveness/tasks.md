# Tasks: Region-Scoped Request Liveness

- [x] **T001** Live root-cause probes (lead, 2026-08-21): refuted the
      ScaleFactor hypothesis, measured out-of-region starvation (7/8 held).
      File: `NaruRemote/Tests/FakeRFBServerKitTests/LiveMacRFBSmokeTests.swift`.
- [x] **T002** FAIL-first pump gates + region-aware fake. File:
      `NaruRemote/Tests/NaruRemoteCoreTests/RFBFramePumpTests.swift`.
- [x] **T003** Pump fix: parked-set owns the region, re-park on viewport
      change, widen on hold, widen counter. File:
      `NaruRemote/Sources/NaruRemoteCore/VNC/RFBFramePump.swift`.
- [x] **T004** Live pump-driven liveness gate.
- [x] **T005** **Simulator E2E liveness gate** (lead, 2026-08-21, after the
      founder asked "증상이 있는지 네가 검증 못하니"): the lead now verifies the
      symptom itself instead of handing it to a device pass.
      `NaruRemote/UITests/StreamLivenessUnderInteractionUITests.swift` drives
      the real app in the iPhone simulator against this Mac's Screen Sharing,
      zooms (which turns region scoping on), pans, and opens the input dock,
      asserting the perf HUD's content-frame counter keeps advancing. The
      counter needed a machine-readable seam — the HUD published it as pixels
      only, which is *why* a UI test could screenshot the freeze but never
      fail on it — so `naru.session.perf.contentFrameCount` now carries it as
      an accessibility value (counts only, already `NARU_PERF_HUD`-gated).
      Measured: green with the fix (`stalledAt=none`), and with the fix
      neutralized it fails at exactly the founder's two moments —
      "Frames stopped after panning" and "Frames stopped after the dock
      opened".
- [ ] **T006** Surface `pipelinedRegionWidenedRequestCount` in the DEBUG
      performance HUD next to `SessionStreamStats`.
- [ ] **T007** Founder re-test on build 5.
