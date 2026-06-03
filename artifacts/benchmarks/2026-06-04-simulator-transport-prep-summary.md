# Simulator Transport-Prep Benchmark

Date: 2026-06-04 KST

Target: iPhone 17 Pro simulator, iOS 26.2

Configuration:

- Synthetic framebuffer: 1920 x 1080
- Iterations: 10
- Command: `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteBenchmarkTests/SyntheticFramePipelineBenchmarkTests test`
- Environment was injected into the booted simulator with `xcrun simctl spawn <device> launchctl setenv ...`.

Results:

| Benchmark | Clock avg | CPU avg | Peak physical memory avg |
| --- | ---: | ---: | ---: |
| Framebuffer allocation + full upload | 8.87 ms | 4.83 ms | 26,341 kB |
| Same-frame upload-gate skip | 0.003 ms | 0.29 ms | 25,693 kB |
| Small dirty-rect upload | 0.65 ms | 0.47 ms | 20,219 kB |
| Steady-state full upload | 3.48 ms | 2.03 ms | 27,177 kB |

Interpretation:

- The same-frame skip path remains effectively free compared with either
  dirty-rect or full-texture upload.
- Small dirty-rect upload is still much cheaper than full upload, so the
  renderer-upload aggregate fields are useful for diagnosing hot sessions.
- The benchmark run initially exposed a stale generated Xcode project that
  omitted `FramebufferUploadPlan.swift`; regenerating `NaruRemote.xcodeproj`
  fixed the simulator benchmark path.
- These are simulator-relative numbers only. Physical iPhone heat/FPS still
  requires a live VNC run with `VNCLiveBenchmark --stream-shape-transport both`
  and a physical-device pass.
