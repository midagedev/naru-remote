# Pixel-Format Isolation Gate Summary — 2026-06-06

This increment adds a benchmark-only low-color gate for the sustained
`iphone-sustained-usability-v2` target. It does not change the app's default
VNC connection path.

## What Changed

- Added `RFBPixelFormat.fullColor32LittleEndian` and
  `RFBPixelFormat.rgb565In32LittleEndian`.
- Let `RFBNetworkClient` optionally send `SetPixelFormat` after `ServerInit`
  and before `SetEncodings`.
- Added stream-shape profiles:
  - `local-low-latency-rgb565`
  - `zrle-compression-0-rgb565`
- Added `--stream-shape-profiles pixel-format-isolation`.
- Added `--stream-shape-gate-preset sustained-v2-pixel-format`, which keeps
  the sustained v2 controlled-stimulus gate shape and swaps in full-color vs
  RGB565 profile pairs.
- Bumped `VNCLiveBenchmark` report schema to v39.

## Verification

- `swift test --filter RFBEncodingTests`
- `swift test --filter RFBRawFramebufferDecoderTests`
- `swift test --filter FakeRFBServerIntegrationTests/testProductionRFBNetworkClientSendsSetPixelFormatAndDecodesRGB565FirstFrame`
- `swift test --filter FakeRFBServerIntegrationTests`
- `swift test --filter BenchmarkStreamShapeGatePresetTests`
- `swift test --filter BenchmarkStreamShapeProfileSelectionTests`
- `swift build --product VNCLiveBenchmark`
- `swift run VNCLiveBenchmark --help | rg -n "gate-preset|pixel-format|schema v39|stream-shape-profiles"`
- `swift run VNCLiveBenchmark --environment-preflight --stream-shape-gate-preset sustained-v2-pixel-format --ask-password --json`

The preflight smoke confirmed the new preset expands to the external-command
stimulus gate without connecting or prompting for a password. With an empty
local benchmark environment it reported only fixed safe setup labels:
`missing-host`, `missing-stimulus-command`, `promptRequested`, `defaulted`, and
`external-command`.

## Interpretation

Run `sustained-v2-pixel-format` after `sustained-v2-core` suggests that
profile, transport, or server encode pressure may be limiting practical iPhone
use. A win here should graduate to live and physical-device verification, not
directly to a production default change.

## Safety

Pixel-format benchmark artifacts may emit only fixed preset/profile labels,
aggregate counts, aggregate timing summaries, aggregate permille ratios, and
existing safe benchmark fields. They must not include host identity,
credentials, port value, stimulus command text, command output, TCP/RFB raw
errors, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
counts, raw payloads, draft text, marked text, or IME state.
