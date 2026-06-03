# Naru Remote Benchmarks

This folder records repeatable benchmark entry points and safe reporting
rules for VNC streaming work. Do not store screenshots, framebuffer
pixels, target hostnames, passwords, cursor pixels, or raw connection
payloads here.

## iPhone Simulator: Synthetic Frame Pipeline

Use the opt-in XCTest benchmarks when investigating heat, low FPS, or
frame-upload regressions without a live VNC server.

```bash
DEVICE_ID=<iPhone simulator UDID from `xcrun simctl list devices`>
xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_RUN_SIM_BENCHMARKS 1
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_SIM_BENCHMARK_WIDTH 1920
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_SIM_BENCHMARK_HEIGHT 1080
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_SIM_BENCHMARK_ITERATIONS 10

xcodebuild \
  -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteBenchmarkTests/SyntheticFramePipelineBenchmarkTests \
  test

xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_RUN_SIM_BENCHMARKS
xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_SIM_BENCHMARK_WIDTH
xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_SIM_BENCHMARK_HEIGHT
xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_SIM_BENCHMARK_ITERATIONS
```

Plain shell environment variables on the `xcodebuild` invocation are not
reliably visible inside the simulator test process. Set them on the
booted simulator with `simctl spawn ... launchctl setenv` first.

The benchmark target measures:

- framebuffer allocation plus full Metal texture upload
- steady-state full Metal texture upload
- steady-state small dirty-rectangle Metal texture upload

Simulator results are useful for relative comparisons across commits.
They do not prove physical iPhone thermal behavior, battery impact, or
real display scheduling. Always close thermal/FPS claims with a physical
iPhone pass.

## Live VNC Target: Encoding And Update Latency

Use the existing live benchmark for real VNC server behavior. Configure
the target only through environment variables or the hidden password
prompt.

```bash
NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_MAC_PASSWORD='...' \
swift run VNCLiveBenchmark \
  --attempts 3 \
  --full-refresh-samples 2 \
  --stream-shape-samples 30 \
  --stream-shape-frame-interval 0.033 \
  --stream-shape-profiles all \
  --continuous-update-samples 3
```

The live benchmark intentionally redacts the target identity and avoids
emitting framebuffer dimensions, pixel payloads, byte counts, cursor
pixels, and raw error descriptions. The stream-shape probe emits
aggregate FPS, update-latency, dirty-rectangle-count, dirty-area
permille, and changed-pixel permille summaries only. By default
stream-shape uses the app's `local-low-latency` profile; pass
`--stream-shape-profiles all` when comparing whether Tight/ZRLE/adaptive
profiles actually improve sustained interaction on the current server.
