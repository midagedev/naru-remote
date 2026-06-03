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
- same-frame upload-gate skip overhead

Simulator results are useful for relative comparisons across commits.
They do not prove physical iPhone thermal behavior, battery impact, or
real display scheduling. Always close thermal/FPS claims with a physical
iPhone pass.

## Physical iPhone: Live Connection Smoke

Use the physical-device UI test before claiming iPhone reachability,
thermal, or sustained-session behavior. Keep the device unlocked and on
the home screen. Pass signing as a command-line build setting rather than
committing a personal team ID to `project.yml`.

```bash
read -rs NARU_PHYSICAL_E2E_PASSWORD
export NARU_PHYSICAL_E2E_PASSWORD
export NARU_PHYSICAL_E2E_HOST=<private Mac address or MagicDNS name>
export NARU_PHYSICAL_E2E_PORT=5900
export NARU_PHYSICAL_E2E_HOST_KIND=privateAddress

xcodebuild \
  -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS,id=<physical-device-id>' \
  -only-testing:NaruRemoteUITests/PhysicalDeviceConnectE2EUITests \
  DEVELOPMENT_TEAM=<local-development-team-id> \
  test

unset NARU_PHYSICAL_E2E_PASSWORD
```

If Xcode reports that the destination may need to be unlocked after a
preparation error, unlock the device and rerun the same command. Do not
store the password, device identifier, screenshots, or diagnostic
payloads in this folder.

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
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --first-frame-profiles stream-shape-profiles \
  --stream-shape-profiles all \
  --stream-shape-transport both \
  --continuous-update-samples 3
```

The live benchmark intentionally redacts the target identity and avoids
emitting framebuffer dimensions, pixel payloads, byte counts, cursor
pixels, and raw error descriptions. The stream-shape probe emits
aggregate FPS, update-latency, dirty-rectangle-count, dirty-area
permille, changed-pixel permille, and renderer upload strategy
summaries only. It also emits fixed-threshold tail buckets for updates
at or above 250 ms / 1000 ms, including only aggregate slow-frame
counts and whether those slow frames were content, full-dirty, or
full-upload classified. By default
stream-shape uses the app's `local-low-latency` profile; pass
`--stream-shape-profiles all` when comparing whether Tight/ZRLE/adaptive
profiles actually improve sustained interaction on the current server.
For targeted longer runs after an all-profile sweep, pass a comma-separated
subset such as `--stream-shape-profiles tight-first,zrle-compression-0,adaptive-good-full`
so the benchmark spends time only on the current candidates.
The default `--stream-shape-empty-backoff app` mode mirrors the app's
sustained empty-update backoff so static-screen benchmark pacing matches
the runtime stream loop; use `none` only when comparing against legacy
fixed idle polling.
Use `--stream-shape-transport both` when comparing request/response
polling against the ContinuousUpdates/Fence overlay before changing the
production transport gate.
In `both` mode, the top-level `streamShapeProbe` remains the first
selected profile/transport as a compatibility summary; use
`streamShapeProfileProbes` for the full profile-by-transport matrix.
For longer stream-shape-only runs, pass `--first-frame-profiles
stream-shape-profiles` to benchmark first-frame latency only for the
same profiles being stream-shaped, or `--first-frame-profiles none` to
skip the first-frame/full-refresh sweep entirely.
