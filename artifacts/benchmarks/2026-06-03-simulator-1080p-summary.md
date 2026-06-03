# Simulator Synthetic Frame Pipeline Benchmark

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
| Framebuffer allocation + full upload | 9.69 ms | 5.18 ms | 33,142 kB |
| Steady-state full upload | 5.24 ms | 2.08 ms | 28,555 kB |
| Small dirty-rect upload | 0.80 ms | 0.49 ms | 21,097 kB |

Interpretation:

- Simulator numbers are useful for commit-to-commit comparisons, not
  final thermal claims.
- Dirty-rectangle upload is much cheaper than full upload in this local
  benchmark, so real-session diagnostics should next measure how often
  live updates fall back to full upload and how large the dirty area is.
- Physical iPhone validation is still required for heat, battery, and
  real display scheduling.
