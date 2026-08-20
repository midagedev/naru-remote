# Feature Specification: Helper Video HEVC Lane

**Feature Branch**: `021-helper-video-hevc`
**Created**: 2026-08-20
**Status**: Implemented 2026-08-20 (grok round + lead review; `swift test`
1686/0 failures, iPhone simulator build green). Bitrate rows provisional;
founder device pass residual (HEVC feel at the reduced bitrate).
**Product**: Naru Remote
**Input**: Founder direction 2026-08-20 "마지막까지 하고 테스트하려고" — finish
the last researched performance lever (NEXT_STEPS 1f lever ④,
`artifacts/research/2026-08-20-streaming-performance-levers.md`), then
TestFlight.

## Ground Truth (code-read 2026-08-20)

- `HelperVideoCodec` is `{h264, unknown}`; the start request's `codec`
  field defaults `.h264` and both `HelperVideoStartRequestPolicy` (App) and
  the helper's `handleStartStreamRequest` descriptor hardcode `.h264`.
- The app runs **no video-capability round trip** before startStream — the
  video lane goes straight to the start request, so negotiation must not
  add a pre-flight.
- Helper encoder (`NaruHelperVideoToolboxPixelBufferAccessUnitEncoder`)
  hardcodes `kCMVideoCodecType_H264` (two sites, lines ~241/~324) and
  extracts parameter sets via
  `CMVideoFormatDescriptionGetH264ParameterSetAtIndex`.
- App renderer (`HelperVideoH264SampleBufferRenderer.swift`) parses Annex-B
  with H.264 NAL typing (`byte & 0x1F`, SPS=7/PPS=8) and builds the format
  description with `CMVideoFormatDescriptionCreateFromH264ParameterSets`.
- Wire AU kinds (`parameterSet`/`keyframe`/`delta`) are codec-agnostic.
- Swift `Codable` ignores unknown JSON keys, and optional fields decode nil
  when absent — the compatibility mechanism this spec builds on.

## Why

HEVC delivers H.264-comparable quality at roughly two-thirds the bitrate —
on the helper lane that compounds with spec 020's caps (readability@30
drops 1.8 → ~1.2 Mbps). Apple hardware support is universal on the target
fleet (HEVC hardware decode since A9 iPhones; encode on Apple Silicon /
T2 Macs), and VideoToolbox low-latency rate control supports HEVC.

## Requirements

- **FR-001 (offer/answer negotiation, zero extra round trips)**: The start
  request body gains an OPTIONAL `acceptsHEVC: Bool?` field; the `codec`
  field keeps carrying `.h264` so legacy decoders never see an unknown enum
  value. A new helper answers in the start response's stream descriptor:
  `codec: .hevc` iff the request offered `acceptsHEVC == true` AND the
  helper's HEVC encode probe passes; otherwise `.h264`. Compatibility
  matrix (each row pinned by a test):
  - old app → new helper: no `acceptsHEVC` key → h264, byte-identical.
  - new app → old helper: unknown key ignored → descriptor h264 → app
    renders h264.
  - new app → new helper without HEVC encode: probe false → h264.
  - new app → new helper with HEVC encode: hevc.
- **FR-002 (codec enum)**: `HelperVideoCodec` gains `hevc`. The descriptor
  is the only wire field that ever carries it (see FR-001).
- **FR-003 (app offer)**: `HelperVideoStartRequestPolicy` gains
  `deviceSupportsHEVCDecode: Bool` (explicit, no default) and sets
  `acceptsHEVC` from it. The model passes it via a new
  `hevcDecodeSupportProvider: @Sendable () -> Bool` init parameter
  (following the `lowPowerModeProvider` pattern) whose default calls
  `VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)`.
- **FR-004 (helper encode)**: The negotiated codec has a **single owner**:
  the request handler computes it (request offer × injected
  `hevcEncodeSupportProbe: @Sendable () -> Bool`, default = a real
  VideoToolbox probe on macOS such as
  `VTCopySupportedPropertyDictionaryForEncoder` for HEVC with the
  low-latency encoder specification; false off-macOS) and the descriptor,
  the pipeline, and the encoder all consume that one decision. The source
  protocol's signal overload from spec 019 is extended to carry the
  negotiated codec (default implementation ignores it, so fixture sources
  compile unchanged). The encoder takes a codec parameter:
  `kCMVideoCodecType_HEVC`, `kVTProfileLevel_HEVC_Main_AutoLevel`,
  parameter sets via `CMVideoFormatDescriptionGetHEVCParameterSetAtIndex`
  (VPS+SPS+PPS, 3 sets); keyframe/delta classification (sync-sample
  attachment) and the spec-019 keyframe signal work unchanged.
- **FR-005 (bitrate table)**: HEVC rows in `NaruHelperVideoRateControlPolicy`
  at ~2/3 of H.264 (readability 800k/1.2M, balanced 1.6M/2.4M, fidelity
  2.7M/4.0M for 15/30 fps) — provisional pending the founder device pass
  (marker in code comment). H.264 rows unchanged.
- **FR-006 (app render)**: The sample-buffer factory keys NAL parsing and
  format-description creation off the negotiated codec: HEVC NAL type is
  `(byte >> 1) & 0x3F`, parameter sets VPS=32/SPS=33/PPS=34,
  `CMVideoFormatDescriptionCreateFromHEVCParameterSets`, 4-byte length
  prefixes as today. `HelperVideoAccessUnitRendering` gains a
  `prepare(codec:)` method with a no-op default; the runner calls it when
  the start response arrives. The H.264 path stays byte-identical
  (regression-pinned by the existing renderer tests).
- **FR-007 (privacy/scope)**: No new logging or diagnostic-export fields
  (`streamCodec` already flows through existing fixed-label state).
  PiP/watch and the VNC lane untouched. File renames (e.g. the
  `H264`-named renderer file) are deliberately out of scope — additive
  diff only.

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — handler tests (**FAIL-first**) | the four FR-001 matrix rows; unmodified handler answers h264 to an HEVC offer |
| `swift test` — encoder round trip (VT, macOS) | HEVC encode of synthetic frames emits a parameterSet AU containing NAL types 32/33/34 and keyframe/delta kinds; spec-019 keyframe signal still forces an IDR under HEVC |
| `swift test` — renderer factory | HEVC parameter sets → format description created; HEVC media AU → displayable sample buffer (mirror the existing H.264 renderer tests); H.264 tests unchanged |
| `swift test` — policy/model | `deviceSupportsHEVCDecode` true → request offers HEVC; false → no offer; old-JSON (no key) decode regression |
| `swift test` — fake-transport E2E | offer → descriptor `.hevc` → rendered frames over the in-process service |
| iPhone simulator build | app target builds |
| Founder device pass (residual) | HEVC lane feels equal-or-better at the reduced bitrate; A/B vs H.264 if it doesn't |

## Residual Risk

- The 2/3 bitrate table is a rule-of-thumb, not measured on this content
  class (terminal text); the device pass judges it, and the rows are
  marked provisional.
- Simulator HEVC decode differs from device hardware paths; the device
  pass covers it.
- Helper Macs without hardware HEVC encode silently stay on H.264 by
  design (probe), so a mixed fleet never regresses.
