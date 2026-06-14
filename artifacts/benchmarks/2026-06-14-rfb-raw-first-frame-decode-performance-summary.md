# RFB Raw First-Frame Decode Performance Summary

Date: 2026-06-14

## Scope

This run isolates the first full-frame Raw VNC decode path used by the
request/response first paint. It does not include live server wait time,
network transfer time, Metal upload, UIKit/SwiftUI layout, or physical-device
thermal behavior.

## Change

- Added an opt-in XCTest benchmark for full-frame Raw first-paint decode.
- Added a full-frame Raw fast path that decodes pixels into a contiguous
  framebuffer replacement instead of calling the bounds-checked per-pixel
  setter.
- Deferred initial black framebuffer materialization until a non-full-frame
  update actually needs it.

## Result

Compared with the same benchmark before the decoder change:

- Clock time stayed more than 20% lower across repeated after-runs; the final
  recheck was about 27% lower.
- CPU time stayed more than 20% lower across repeated after-runs; the final
  recheck was about 27% lower.
- CPU cycles stayed more than 20% lower across repeated after-runs; the final
  recheck was about 26% lower.
- Retired CPU instructions were about 18% lower.
- Peak-memory readings were noisy and are not treated as an improvement claim.

This is a clear simulator-side CPU improvement for the local decode part of
the first-frame path. It does not by itself prove live VNC FPS improvement,
because current live FPS gates are still dominated by server/transport cadence.

## Verification

```bash
env NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=5 \
  xcodebuild \
    -project NaruRemote.xcodeproj \
    -scheme NaruRemote \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
    -only-testing:NaruRemoteBenchmarkTests/RFBRawDecodeBenchmarkTests/testFullFrameRawFirstPaintDecodeBenchmark \
    test
```

Additional decoder regression coverage:

```bash
swift test --filter 'RFBFramebufferDecoderTests|RFBRawFramebufferDecoderTests|RFBTightDecoderTests|RFBZrleDecoderTests'
```

The benchmark is intentionally synthetic and contains no live target hostnames,
passwords, cursor pixels, screenshots, or raw connection payloads.
