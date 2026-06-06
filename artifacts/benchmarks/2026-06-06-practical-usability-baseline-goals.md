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

`iphone-sustained-usability-v2` remains the active target for normal sustained
streaming work. `iphone-poor-network-traffic-v1` is now a required companion
target for changes intended to improve cellular, lossy Wi-Fi, Tailnet relay, or
otherwise constrained links.

Entry criteria for a larger optimization PR:

- Use a redacted schema v61 live `VNCLiveBenchmark` run with
  `streamShapeProfileGates`, controlled stimulus, and the appropriate practical
  target whenever a live target is available.
- For poor-network work, run or explicitly defer
  `sustained-v2-constrained-cellular-app-low-traffic` so startup area,
  sustained request area, first-byte wait, and payload-read pressure are judged
  together.
- Treat the profile gate as the first decision screen:
  - `fail`: do not promote the profile or cadence change until the issue-code
    union is resolved.
  - `warning`: require an explicit artifact judgment before using it as a
    candidate.
  - `pass`: eligible for physical iPhone verification only.
- Do not change production streaming defaults until sustained-usability and
  poor-network traffic gates are green or explicitly accepted as warnings, and
  a 10 minute physical iPhone hand-feel/thermal pass confirms immediate local
  zoom/pan, reliable Compose route diagnostics, and no `.serious` or
  `.critical` thermal state.

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
start from live schema v61 profile/traffic gates and physical iPhone hand-feel
evidence:

- High request area or payload-read pressure points toward traffic reduction:
  pixel format, encoding profile, first-useful-paint, or visible-region
  request strategy.
- Low received/content hit-rate points toward target reachability, request
  cadence, transport behavior, or stimulus assumptions.
- Good hit-rate with slow content-bearing updates points toward server/network
  wait, decode/apply, or physical-device pacing pressure.
- A passing schema v61 gate that still feels stepped or hot on the phone points
  toward viewport scheduling, input routing, thermal policy, or device pacing
  rather than simulator renderer upload.

## Live Benchmark Status

The current live evidence is no longer green for default promotion: RGB565
low-traffic candidates can survive constrained-cellular startup, but sustained
samples remain first-byte-wait/update-cadence dominated. The next live run
should use the schema v61 gate shapes documented in the benchmark README and
keep target identity, credentials, framebuffer dimensions, coordinates, pixels,
cursor pixels, byte counts, raw samples, raw payloads, raw errors, external
command text, command output, draft text, marked text, and IME state out of
artifacts.

## Verification

- iPhone 17 Pro simulator benchmark:
  - Result: passed with `NARU_RUN_SIM_BENCHMARKS=1`, 1920x1080, 10 iterations.
- Live target environment precheck:
  - Result: target, credential, and stimulus environment values were absent in
    the current shell, so no live run was attempted.
