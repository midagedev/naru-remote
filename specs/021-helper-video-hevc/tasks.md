# Tasks: Helper Video HEVC Lane

- [x] **T001** Wire vocabulary: `hevc` case on `HelperVideoCodec`, optional
      `acceptsHEVC` on `HelperVideoStartStreamRequestBody`, compat decode
      tests (old JSON without the key). File: `HelperVideoTransport.swift`
      (+ `HelperVideoState.swift` for the enum).
- [x] **T002** Helper negotiation (**FAIL-first**): injected
      `hevcEncodeSupportProbe` on `NaruHelperVideoTransportRequestHandler`,
      descriptor answers per the FR-001 matrix.
- [x] **T003** Helper encode: codec parameter through pipeline/sources into
      `NaruHelperVideoToolboxPixelBufferAccessUnitEncoder` (HEVC session,
      HEVC parameter-set extraction); HEVC bitrate rows in
      `NaruHelperVideoRateControlPolicy`. VT round-trip tests incl.
      spec-019 keyframe signal under HEVC.
- [x] **T004** App offer: `deviceSupportsHEVCDecode` on
      `HelperVideoStartRequestPolicy` + `hevcDecodeSupportProvider` model DI.
- [x] **T005** App render: codec-keyed NAL parsing + HEVC format
      description in the sample-buffer factory; `prepare(codec:)` on
      `HelperVideoAccessUnitRendering` (no-op default) called by the runner
      on start response. HEVC renderer tests mirroring the H.264 suite.
- [x] **T006** Fake-transport E2E: HEVC offer → `.hevc` descriptor →
      rendered frames.
- [x] **T007** Lead review (2026-08-20): diff read in full — negotiation is
      single-owner in the handler with an injected probe; omit-nil
      `acceptsHEVC` keeps old-helper request bytes identical; H.264 paths
      additive-only. One lead cleanup: removed the now-dead H.264-only
      `isParameterSet` property on the NAL unit (codec-aware classification
      lives on the factory) so it cannot misclassify HEVC later.
      `swift test` from cold: 1686 tests, 0 failures. `xcodegen` + iPhone
      17 Pro simulator build green. Committed; TestFlight build follows.
