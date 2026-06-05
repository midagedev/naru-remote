# 2026-06-06 Practical Usability Baseline Goals

## Trigger

The streaming work is moving from small diagnostics and isolated tuning into
larger changes that may affect request cadence, encoding profile, startup
preflight, viewport interaction scheduling, and production defaults. This
artifact pins the next decision surface so each larger PR answers the same
question: does it move Naru Remote closer to a sustained iPhone VNC session
that feels smooth, keeps Compose reliable, and does not heat the device
uncomfortably?

## Baseline Target

`iphone-sustained-usability-v2` remains the active target for new streaming
work.

Entry criteria for a larger optimization PR:

- Use a redacted schema v37 live `VNCLiveBenchmark` run with
  `streamShapeProfileGates` and controlled stimulus whenever a live target is
  available.
- Treat the profile gate as the first decision screen:
  - `fail`: do not promote the profile or cadence change until the issue-code
    union is resolved.
  - `warning`: require an explicit artifact judgment before using it as a
    candidate.
  - `pass`: eligible for physical iPhone verification only.
- Do not change production streaming defaults until a 10 minute physical iPhone
  hand-feel and thermal pass confirms immediate local zoom/pan, reliable
  Compose route diagnostics, and no `.serious` or `.critical` thermal state.

## Simulator Frame-Pipeline Baseline

Command shape:

```bash
DEVICE_ID=<booted-iPhone-simulator-UDID>
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
```

Safe aggregate results:

| benchmark | clock avg | CPU avg | peak physical memory avg |
| --- | ---: | ---: | ---: |
| Full framebuffer allocation plus upload | 9 ms | 5 ms | 30190 kB |
| Steady-state full upload | 4 ms | 2 ms | 28904 kB |
| Small dirty-rectangle upload | about 0.5 ms | about 0.6 ms | 21100 kB |
| Same-frame upload-gate skip | about 0.003 ms | about 0.3 ms | 17637 kB |

Result: the clean simulator benchmark run passed.

## Interpretation

The simulator result does not prove physical-device thermal comfort, but it
does make renderer upload alone a weak primary suspect for the current reported
low frame rate and heat. The next larger implementation unit should therefore
start from live v37 profile gates and physical iPhone hand-feel evidence:

- Low received/content hit-rate points toward target reachability, request
  cadence, transport behavior, or stimulus assumptions.
- Good hit-rate with slow content-bearing updates points toward server/network
  wait, decode/apply, or physical-device pacing pressure.
- A passing v37 gate that still feels stepped or hot on the phone points toward
  viewport scheduling, input routing, thermal policy, or device pacing rather
  than simulator renderer upload.

## Live Benchmark Status

A redacted live v37 benchmark was not executed in this increment because the
current shell did not provide live target or stimulus environment values. The
next live run should use the same v37 gate shape documented in the benchmark
README and keep target identity, credentials, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads, raw
errors, external command text, command output, draft text, marked text, and IME
state out of artifacts.

## Verification

- iPhone 17 Pro simulator benchmark:
  - Result: passed with `NARU_RUN_SIM_BENCHMARKS=1`, 1920x1080, 10 iterations.
- Live target environment precheck:
  - Result: target, credential, and stimulus environment values were absent in
    the current shell, so no live run was attempted.
