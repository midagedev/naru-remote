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
- [ ] **T005** App-model liveness gate over a region-aware fake connector
      (the layer above the pump: viewport change → dock open → frames keep
      being published). Closes the simulator-level gap the founder named.
- [ ] **T006** Surface `pipelinedRegionWidenedRequestCount` in the DEBUG
      performance HUD next to `SessionStreamStats`.
- [ ] **T007** Founder re-test on build 5.
