# Simulator Redraw Gate Benchmark

Date: 2026-06-03 KST

Target: iPhone 17 Pro simulator, iOS 26.2

Configuration:

- Synthetic framebuffer: 1920 x 1080
- Iterations: 5
- Command: `xcodebuild -quiet -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteBenchmarkTests/SyntheticFramePipelineBenchmarkTests test`
- Environment was injected into the simulator with `xcrun simctl spawn <device> launchctl setenv ...`.

Results:

| Benchmark | Clock avg | CPU avg | Peak physical memory avg |
| --- | ---: | ---: | ---: |
| Framebuffer allocation + full upload | 7.27 ms | 4.36 ms | 26,811 kB |
| Same-frame upload-gate skip | 0.003 ms | 0.28 ms | 16,994 kB |
| Small dirty-rect upload | 0.62 ms | 0.54 ms | 19,874 kB |
| Steady-state full upload | 3.36 ms | 1.98 ms | 26,828 kB |

Interpretation:

- The upload-gate skip path is effectively free compared with a full
  Metal texture upload in this simulator benchmark.
- The same-frame redraw gate prevents SwiftUI-only updates from asking
  the Metal view to redraw when no framebuffer was enqueued, so cursor
  overlay and control-bar state changes avoid both duplicate upload and
  duplicate texture draw requests.
- Simulator numbers are relative indicators only. Physical iPhone
  validation is still required for heat, battery, and display pacing.
