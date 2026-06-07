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

For the app-side helper-video path, run the companion opt-in benchmark:

```bash
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_RUN_SIM_BENCHMARKS 1
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_SIM_BENCHMARK_ITERATIONS 10
xcrun simctl spawn "$DEVICE_ID" launchctl setenv NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES 4

xcodebuild \
  -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteBenchmarkTests/HelperVideoAppRunnerBenchmarkTests \
  test

xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES
xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_SIM_BENCHMARK_ITERATIONS
xcrun simctl spawn "$DEVICE_ID" launchctl unsetenv NARU_RUN_SIM_BENCHMARKS
```

This measures finite helper-video H.264 access units through the app session
runner and CoreMedia sample-buffer factory. On macOS SwiftPM runs, the same
test target also includes an optional VideoToolbox synthetic helper source when
the host encoder accepts the request.

Simulator results are useful for relative comparisons across commits.
They do not prove physical iPhone thermal behavior, battery impact, or
real display scheduling. Always close thermal/FPS claims with a physical
iPhone pass.

Current baseline artifact:
`artifacts/benchmarks/2026-06-06-practical-usability-baseline-goals.md`.
That run keeps renderer upload as a regression guard but moves the next large
optimization unit toward live profile gates and physical iPhone
hand-feel/thermal verification.
Current live routing artifact:
`artifacts/benchmarks/2026-06-06-sustained-v2-core-live-routing-baseline.md`.
That run uses schema v41's report-level decision to choose
`inspectServerTransportCadence` as the next large benchmark unit.
Current transport/cadence artifact:
`artifacts/benchmarks/2026-06-06-sustained-v2-core-v42-transport-cadence-baseline.md`.
That run confirms v42 exposes repeated ContinuousUpdates connection failure at
the top level and motivates the schema v43 transport/cadence diagnosis.
Current operating target artifact:
`artifacts/benchmarks/2026-06-06-sustained-usability-operating-target.md`.
Use this promotion ladder for larger PRs: benchmark green first, 10 minute
physical iPhone green second, and production default changes only after both
passes.
Current ContinuousUpdates confirmation artifact:
`artifacts/benchmarks/2026-06-06-continuous-updates-confirmation-gate-smoke.md`.
That smoke verifies unconfirmed ContinuousUpdates support is reported as a fixed
compatibility label instead of being hidden behind request/response fallback.
Current physical interaction gate artifact:
`artifacts/benchmarks/2026-06-06-physical-interaction-triage-gate-summary.md`.
Schema v29 adds `physicalGateVerdict` so the 10 minute iPhone gate can block
production default promotion even when the detailed diagnostic verdict is only a
warning.
Current physical sustained candidate gate artifact:
`artifacts/benchmarks/2026-06-06-physical-sustained-candidate-gate-summary.md`.
The opt-in UI test now injects fixed candidate labels, exercises viewport /
trackpad / Compose paths, and emits a delayed active-session diagnostic export.
Current helper-video capture probe artifact:
`artifacts/benchmarks/2026-06-06-helper-video-capture-probe-summary.md`.
The macOS helper now exposes a ScreenCaptureKit permission/capture-source
catalog probe before encoder or stream transport work begins.
Current helper-video encoder prototype artifact:
`artifacts/benchmarks/2026-06-06-helper-video-encoder-prototype-summary.md`.
The macOS helper now gates a VideoToolbox H.264 session-prepare prototype
behind `NARU_HELPER_VIDEO_ENCODER_PROTOTYPE`.
Current helper-video app runner benchmark artifact:
`artifacts/benchmarks/2026-06-07-helper-video-app-runner-sim-benchmark-summary.md`.
The app benchmark now exercises the finite helper-video access-unit path
through visual transport selection and sample-buffer creation without requiring
Screen Recording permission.
Current helper-video connect bootstrap artifact:
`artifacts/benchmarks/2026-06-07-helper-video-connect-bootstrap-summary.md`.
The app model now starts helper-video after the first VNC framebuffer for
enabled private-network profiles, keeps VNC input/control active, and falls back
to VNC with fixed helper-video labels when helper start fails.
Current helper-video network bootstrap smoke artifact:
`artifacts/benchmarks/2026-06-07-helper-video-network-bootstrap-smoke-summary.md`.
The opt-in app benchmark now composes first-frame VNC bootstrap with the real
authenticated helper-video TCP server/client path before the physical live video
gate.
Current helper-video auth transport artifact:
`artifacts/benchmarks/2026-06-06-helper-video-auth-transport-summary.md`.
The helper-video request contract now signs capability/start/keyframe/stop
request envelopes with HMAC proof material scoped to saved profile fingerprints.
Current helper-video iOS decode prototype artifact:
`artifacts/benchmarks/2026-06-06-helper-video-ios-decode-prototype-summary.md`.
The app can convert fake Annex-B H.264 helper-video access units into
CoreMedia sample buffers and route them to an AVSampleBufferDisplayLayer
without logging payload bytes.
Current helper-video environment live comparison artifact:
`artifacts/benchmarks/2026-06-06-helper-video-env-live-comparison-summary.md`.
The constrained-cellular live VNC gate uses environment-sourced credentials
and confirms the helper-video candidate is still benchmark-only disabled until
the live access-unit sender/listener lands.
Current helper-video live readiness artifact:
`artifacts/benchmarks/2026-06-06-helper-video-live-readiness-benchmark-summary.md`.
The live env preflight is runnable, the external synthetic helper process path
passes, the external ScreenCaptureKit helper path is blocked by fixed
permission-missing labels, and a short constrained-cellular VNC run still
routes the next large unit toward live helper-video capture/decode evidence.
Current external helper ScreenCaptureKit permission delegation artifact:
`artifacts/benchmarks/2026-06-06-external-helper-screen-capture-permission-delegation-summary.md`.
Schema v4 preflight now reports `delegatedToHelper` for external-helper
ScreenCaptureKit probes so the helper process, not `VNCLiveBenchmark`, owns the
macOS Screen Recording permission result.
Current helper Screen Recording permission identity artifact:
`artifacts/benchmarks/2026-06-06-helper-screen-recording-permission-identity-summary.md`.
Helper CLI schema v2 adds fixed `permissionIdentity` labels; the current
development helper reports `swiftPMBuildArtifact` plus
`useStableHelperExecutable`, so the next live helper-video work should grant a
stable helper executable or app bundle rather than the transient SwiftPM build
artifact.
Current stable dev helper app wrapper artifact:
`artifacts/benchmarks/2026-06-07-helper-dev-app-signing-summary.md`.
The development wrapper now prefers a single local Apple Development signing
identity when available, reports only a fixed signing label, reports
`appBundle` plus `grantAppBundle`, passes the external synthetic encoded
helper-video smoke, and leaves ScreenCaptureKit blocked only on the helper app
bundle's missing Screen Recording approval.
Current external helper capability preflight artifact:
`artifacts/benchmarks/2026-06-07-external-helper-capability-preflight-summary.md`.
Schema v5 runs the selected helper's safe `--video-capability` before
`external-helper-screen-capturekit-tcp` and now blocks setup with
`grant-helper-video-app-screen-recording-permission` when the helper app bundle
lacks Screen Recording permission.
Current external helper timeout preflight artifact:
`artifacts/benchmarks/2026-06-07-external-helper-timeout-preflight-summary.md`.
Schema v6 bounds the external helper capability wait and emits fixed
`timedOut` labels instead of letting setup diagnostics block.
Current helper-video probe-only artifact:
`artifacts/benchmarks/2026-06-07-helper-video-probe-only-summary.md`.
`VNCLiveBenchmark --helper-video-probe-only` runs helper-video probes without
live VNC target credentials, so helper setup can be checked before full
constrained-cellular VNC comparisons.
Current launchctl live benchmark runner artifact:
`artifacts/benchmarks/2026-06-07-launchctl-live-benchmark-runner-summary.md`.
The wrapper imports live/helper values from `launchctl` without printing them,
confirms external synthetic helper-video is still green, confirms
`NaruHelperDev` Screen Recording permission is still missing, and records the
current short constrained-cellular VNC fallback failure as
`first-frame-payload-read-failed` on the receive path.
Current helper readiness sweep artifact:
`artifacts/benchmarks/2026-06-07-helper-readiness-sweep-summary.md`.
The launchctl runner now has a fixed helper capability/preflight/synthetic
probe/ScreenCaptureKit probe sweep. Current live credentials are configured via
environment labels and the synthetic helper-video path passes, but the true
ScreenCaptureKit helper-video live gate remains blocked by missing Screen
Recording permission for the stable helper app bundle.
Current helper Screen Recording setup artifact:
`artifacts/benchmarks/2026-06-07-helper-screen-recording-setup-summary.md`.
The launchctl runner now has a fixed `screen-recording-setup` mode that checks
helper capability, runs the explicit permission request, opens the macOS Screen
Recording settings pane, and rechecks capability without printing unsafe
details. The current setup still requires the user to grant Screen Recording
to the stable helper app bundle and rerun the readiness sweep.
Current launchctl startup glance scale sweep:
`artifacts/benchmarks/2026-06-07-launchctl-glance-scale-sweep-runner-summary.md`.
Use `scripts/run-naru-live-benchmark.sh glance-scale-sweep` to compare
0.45/0.35/0.25 under one fixed short constrained-cellular app-low-traffic
shape. The current run keeps `0.25` as the best benchmark/physical-gate
candidate because it improves `local-low-latency-rgb565` from failure to
warning with a `19` permille first-frame request area, but the overall
app-low-traffic gate remains failed and needs physical iPhone validation before
any default promotion.
Current launchctl 0.25 duration probe:
`artifacts/benchmarks/2026-06-07-glance-025-duration-probe-summary.md`.
Use `scripts/run-naru-live-benchmark.sh glance-025-duration-probe` to rerun the
fixed VNC-only poor-network candidate: `visible-glance` scale `0.25`,
`local-low-latency-rgb565`, `request-response`, `viewport-phone-portrait`,
`constrained-cellular`, and a 12 second duration-only sustained phase. The
current live run exits cleanly and reaches `warning`, with a `19` permille
first-frame request area, `1000/960/960` received/content/content-response
sample permille, `1.99` content FPS, `480` ms average update, `628` ms p95
update, and `receivePath` as the remaining primary constraint.
Current launchctl 0.25 profile sweep:
`artifacts/benchmarks/2026-06-07-glance-025-profile-sweep-summary.md`.
Use `scripts/run-naru-live-benchmark.sh glance-025-profile-sweep` to compare
the current app-selectable stream profile candidates under the same fixed
`0.25` poor-network shape. The current live run completes all five profiles
and keeps `local-low-latency-rgb565` as the strongest poor-network candidate:
it records `1.99` content FPS, `501` ms average update, `625` ms p95 update,
`0` renderer full-upload permille, and `1000/1000/1000`
received/content/content-response sample permille. Other profiles remain worse
on first-frame receive time, renderer upload pressure, content hit rate, or
startup connectivity, so the next work should inspect update wait timing and
server transport cadence rather than trying another quick profile default flip.
Current 10fps remote-desktop target artifact:
`artifacts/benchmarks/2026-06-07-remote-desktop-10fps-target-summary.md`.
`iphone-remote-desktop-10fps-v1` is the new product-grade sustained smoothness
target: content FPS below `10` is a failure, not a warning. Use
`scripts/run-naru-live-benchmark.sh glance-025-10fps-duration-probe` to run the
current `0.25` + `local-low-latency-rgb565` candidate against that stricter
target. Direct `VNCLiveBenchmark` runs can use
`--stream-shape-gate-preset remote-desktop-10fps` to reproduce the same fixed
VNC gate without hand-copying the launchctl wrapper's option list. The current
live run records `1.97` content FPS, `508` ms average
update, `627` ms p95 update, `626` ms first-byte wait p95, and a `fail`
decision with `content-fps-failed`, `average-update-failed`,
`p95-update-failed`, `first-byte-wait-failed`, and
`first-frame-payload-read-failed`.
Current remote desktop 10fps readiness artifact:
`artifacts/benchmarks/2026-06-07-remote-desktop-10fps-readiness-summary.md`.
Use `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness` to run
the fixed 10fps VNC gate together with helper-video capability/preflight,
external synthetic H.264, and external ScreenCaptureKit checks in one
privacy-safe JSON object. The current live run confirms that VNC is still a
10fps product failure (`1.89` content FPS, `508` ms average update, `626` ms
p95 update, `receivePath` primary constraint), while external synthetic
helper-video passes and true ScreenCaptureKit helper-video remains blocked by
missing Screen Recording permission for the helper app bundle.
Current launchctl request pipeline sweep:
`artifacts/benchmarks/2026-06-07-launchctl-request-pipeline-sweep-summary.md`.
The launchctl runner now has a VNC-only depth 1/2/3 sweep; the first run keeps
every depth below the poor-network target, so request pipelining remains
benchmark-only.
Current trackpad follow coupling tuning artifact:
`artifacts/benchmarks/2026-06-07-trackpad-follow-coupling-tuning-summary.md`.
Zoomed trackpad follow-pan coupling is raised while keeping visible cursor
travel finger-paced and preserving the existing tiny-sample no-snap guards.
Current physical glance candidate follow-up:
`artifacts/benchmarks/2026-06-06-physical-glance-candidate-gate-summary.md`.
It adds the low-traffic RGB565 stream labels and startup glance scale label to
the physical gate so 0.45/0.35/0.25 can be compared on the phone without a
rebuild.
Current sustained usability candidate contract:
`artifacts/benchmarks/2026-06-06-sustained-usability-candidate-contract.md`.
Use this as the merge contract for larger default-changing PRs: benchmark-green
first, physical iPhone green second, rollback note before production default
changes.
Current live preflight action artifact:
`artifacts/benchmarks/2026-06-06-live-preflight-action-hints-summary.md`.
Schema v2 adds fixed setup action labels so missing benchmark inputs route to a
next action without exposing host, credential, port, or stimulus command values.
Schema v4 reports helper-video ScreenCaptureKit permission readiness using only
fixed status, issue, and setup-action labels. In-process ScreenCaptureKit probes
preflight the benchmark process; external-helper ScreenCaptureKit probes report
`delegatedToHelper` and let the helper process return permission failures.
Schema v5 additionally runs the selected external helper's safe
`--video-capability` for `external-helper-screen-capturekit-tcp`, so helper app
bundle permission gaps are surfaced before the live benchmark run with fixed
identity and setup-action labels only.
Schema v6 bounds that external helper capability wait and reports
`helper-video-external-helper-timed-out` plus `inspect-helper-video-capability`
if the helper executable does not answer.
The helper-video probe-only report wraps the same helper-video comparison schema
and adds only the fixed selected probe-mode label. It omits live target
credentials, helper executable paths, endpoints, tokens, frame payloads, byte
counts, dimensions, coordinates, raw OS errors, and exact helper timings.
Current helper-video fake comparison artifact:
`artifacts/benchmarks/2026-06-06-helper-video-fake-transport-comparison-summary.md`.
Schema v67 adds a visual transport comparison envelope so `vnc` and
`helper-video` candidates can be reported with fixed labels before a live
helper stream exists.
Current helper-video profile guard artifact:
`artifacts/benchmarks/2026-06-06-helper-video-profile-guard-summary.md`.
The app now models saved helper-video opt-in state, disables/revokes helper
video with fixed labels, and blocks public-host helper-video attempts before a
helper capture prototype exists.
Latest completed live sustained-v2-core baseline:
`artifacts/benchmarks/2026-06-06-live-sustained-v2-core-baseline.md`.
This run is not benchmark-green: ContinuousUpdates is still
`failed-before-samples`, request/response is the recommended fallback but remains
`below-target`, and the next large unit is
`inspectContinuousUpdatesConnection`.
List future completed live baselines here newest-first.
Current request/response isolation preset artifact:
`artifacts/benchmarks/2026-06-06-sustained-v2-request-response-preset-summary.md`.
Use `sustained-v2-request-response` after ContinuousUpdates is already known to
be blocked and the next question is which request/response profile or cadence
candidate deserves the same sustained v2 gate. The first live run with this
preset routes to `compareRequestResponseEncodingProfiles`, with
`adaptive-good-full` as the order-neutral request/response label, but remains
not benchmark-green.
Current request/response probe isolation cleanup:
`artifacts/benchmarks/2026-06-06-request-response-preset-skips-continuous-probe.md`.
The request/response preset now sets `continuousUpdateSamples` to 0 so the
standalone `continuousUpdatesProbe` reports `not-tested` instead of adding known
ContinuousUpdates blocker noise to request/response-only comparisons.
Current controlled stimulus cadence artifact:
`artifacts/benchmarks/2026-06-06-stimulus-cadence-target-summary.md`.
Schema v44 reports the configured stimulus frame interval and expected FPS,
and passes the same cadence to `VNCLiveStimulusWindow`, so low content FPS can
be interpreted against a known 12 Hz controlled stimulus before changing app
defaults.
Current steady-stream gate alignment artifact:
`artifacts/benchmarks/2026-06-06-steady-stream-v2-gate-summary.md`.
The sustained v2 presets now keep viewport-interaction mode off so the 8fps
content target measures steady stream cadence. Active zoom/pan smoothness stays
gated by the physical iPhone pass and by custom interaction experiments.
Current request/response ZRLE isolation preset artifact:
`artifacts/benchmarks/2026-06-06-sustained-v2-zrle-isolation-preset-summary.md`.
Use `sustained-v2-zrle-isolation` after the request/response core matrix says
profile/cadence is still the next large unit. The first live v45 run shows pure
ZRLE and cursor-only ZRLE reduce client/tile tail, but every candidate still
misses the 8fps steady-stream target, so the next unit routes to
`inspectServerTransportCadence` before production default changes.
Current request/response zero-delay cadence artifact:
`artifacts/benchmarks/2026-06-06-sustained-v2-zrle-zero-delay-summary.md`.
Use `sustained-v2-zrle-zero-delay` to test whether removing post-content
request delay is enough to reach the sustained target. The first live v46 run
raises the strongest ZRLE candidates to roughly 7fps but still misses 8fps and
keeps max p95 near 500 ms, so the next unit remains transport cadence tuning
instead of production default promotion.
Current request cadence health artifact:
`artifacts/benchmarks/2026-06-06-request-cadence-health-report-summary.md`.
Schema v47 adds `streamShapeRequestCadenceHealth` so request/response gates
separate sample-hit health from p95 update tail. The first live v47 zero-delay
run reports high content hit, low unanswered-request pressure, and p95-failed
latency, so the next unit should tune or instrument the request pacing window
and update-wait timing rather than changing production defaults.
Current request pacing window sweep artifact:
`artifacts/benchmarks/2026-06-06-request-pacing-window-sweep-summary.md`.
Schema v48 adds fixed `streamShapePacingWindows` labels to stream-shape probes,
aggregates, gates, and recommendations. Use
`sustained-v2-zrle-pacing-sweep` to hold `zrle-compression-0-clipboard`
constant and compare `zero-content-delay`, `app-balanced-30hz`, and
`stimulus-aligned-12hz`. The first live v48 sweep keeps zero-content-delay as
the best candidate by average update latency and FPS, but still misses the v2
target, so the next unit should inspect request/update wait-tail timing.

## Physical iPhone: Live Connection Smoke

Use the physical-device UI test before claiming iPhone reachability,
thermal, or sustained-session behavior. Keep the device unlocked and on
the home screen. Pass signing as a command-line build setting rather than
committing a personal team ID to `project.yml`.

Current physical-device preflight artifact:
`artifacts/benchmarks/2026-06-07-physical-device-team-inference-summary.md`.
Use `scripts/run-naru-live-benchmark.sh physical-device-preflight` before the
long physical UI gates. It reports only fixed labels for device selection,
signing identity, development team, Xcode account, provisioning, and build-check
status. The device-selection check is intentionally iPhone-only, so a connected
iPad does not satisfy the T030/T031 gate. If exactly one local Apple
Development team is available, the runner may use it for the captured build
check and report only `developmentTeamStatus=inferred`.

Current bounded VNC profile sweep artifact:
`artifacts/benchmarks/2026-06-07-bounded-vnc-profile-sweep-summary.md`.
Use `scripts/run-naru-live-benchmark.sh bounded-vnc-profile-sweep` when checking
whether the current live target can complete the fixed VNC candidate set without
hanging. The mode compares only fixed safe profile labels and returns a fixed
timeout JSON label if the wall-clock guard fires. Follow-up artifact
`artifacts/benchmarks/2026-06-07-bounded-vnc-profile-phase-attribution-summary.md`
adds fixed `lastPhaseLabel` values to guarded failures; the current live timeout
reaches `benchmark-running`, so the remaining bottleneck is inside the bounded
VNC benchmark path rather than SwiftPM setup.

Current per-profile bounded VNC drilldown artifact:
`artifacts/benchmarks/2026-06-07-bounded-vnc-profile-drilldown-summary.md`.
Use `scripts/run-naru-live-benchmark.sh bounded-vnc-profile-drilldown` when the
all-profile bounded sweep times out. It builds once, runs the fixed VNC
candidates one at a time with a per-profile wall-clock guard, and reports only
catalog profile labels plus fixed failure/phase labels. The current live
drilldown shows all three candidates timing out in `benchmark-running`, which
points to a broader benchmark/VNC runtime bottleneck rather than a single
encoding profile.

Correction/current bounded VNC profile artifact:
`artifacts/benchmarks/2026-06-07-bounded-vnc-subphase-progress-summary.md`.
The timeout result above was caused by the runner combining candidate profiles
with `--stream-shape-gate-preset sustained-v2-core`, whose preset profile set
overrode the intended candidates. The runner now owns a
`--safe-progress-label-file` temp hook for timeout diagnostics and spells out
the sustained-v2-compatible bounded options directly. Current live bounded
results complete: `tight-first` and `adaptive-good-full` report warning
verdicts, while `zrle-compression-0` reports fail.

Current bounded VNC candidate stability artifact:
`artifacts/benchmarks/2026-06-07-bounded-vnc-candidate-stability-summary.md`.
Use `scripts/run-naru-live-benchmark.sh bounded-vnc-candidate-stability` after a
corrected bounded sweep leaves warning candidates. The current live stability
run repeats `tight-first` and `adaptive-good-full` three times each. Both gates
still fail overall; `tight-first` is the better working candidate, but it is not
ready for production-default promotion because it has zero pass runs and a
client-decode primary constraint.

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

For the larger sustained candidate gate, keep the same target variables and run
the opt-in sustained UI test. The recommended production-promotion duration is
600 seconds. The three candidate labels below are required; the test fails
configuration early rather than silently running with the phone's existing
settings or defaults. The fourth label, startup glance scale, is required so
low-traffic RGB565 candidates can compare 0.45/0.35/0.25 first-useful-paint
quality without rebuilding. The test injects only fixed candidate labels into
the app, performs viewport pinch/pan, trackpad movement, and a Compose send
attempt, then keeps the session alive while the app emits a delayed diagnostic
JSON block through the safe `makeDiagnosticExport()` path.

```bash
read -rs NARU_PHYSICAL_E2E_PASSWORD
export NARU_PHYSICAL_E2E_PASSWORD
export NARU_PHYSICAL_E2E_HOST=<private Mac address or MagicDNS name>
export NARU_PHYSICAL_E2E_PORT=5900
export NARU_PHYSICAL_E2E_HOST_KIND=privateAddress
export NARU_PHYSICAL_E2E_SUSTAINED_SECONDS=600
export NARU_PHYSICAL_E2E_STREAM_POWER_MODE=balanced
export NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE=local-low-latency-rgb565
export NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE=one-hidden-frame
export NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE=glance-025

xcodebuild \
  -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS,id=<physical-device-id>' \
  -only-testing:NaruRemoteUITests/PhysicalDeviceConnectE2EUITests/testPhysicalDeviceSustainedCandidateGate \
  DEVELOPMENT_TEAM=<local-development-team-id> \
  test

unset NARU_PHYSICAL_E2E_PASSWORD
```

Use the last `NARU_DIAGNOSTIC_EXPORT_BEGIN` / `NARU_DIAGNOSTIC_EXPORT_END`
block from the xcodebuild log as the diagnostic evidence. The production
promotion signal is
`sustainedSessionAssessment.physicalGateVerdict == "pass"` with matching manual
hand-feel notes; `blocked` means the next PR should follow
`primaryConstraint` / `recommendedNextProbe` instead of changing defaults.
For a current-baseline run, use `standard` plus `standard-045`. For low-traffic
poor-network candidates, use either `local-low-latency-rgb565` or
`zrle-compression-0-rgb565`, then compare `standard-045`, `minimal-035`, and
`glance-025` as separate fixed labels.
Set `NARU_PHYSICAL_E2E_COMPOSE_TEXT` only when intentionally testing a specific
IME payload; the UI test attachment records only `ascii`/`unicode`, never the
text.

If Xcode reports that the destination may need to be unlocked after a
preparation error, unlock the device and rerun the same command. Do not
store the password, device identifier, screenshots, or diagnostic
payloads in this folder.
If Xcode stops before install with missing iOS development provisioning
profiles, create or refresh the local development profiles in Xcode first (or
run the command with an explicit, intentional provisioning update flow). Treat
that as signing setup, not as VNC/session evidence.

## Live VNC Target: Encoding And Update Latency

Use the existing live benchmark for real VNC server behavior. Configure
the target only through environment variables or the hidden password
prompt.

Before running a live gate, use the environment preflight to confirm local
setup without connecting or prompting for a password:

```bash
swift run VNCLiveBenchmark \
  --environment-preflight \
  --stream-shape-gate-preset sustained-v2-core \
  --ask-password \
  --json
```

The preflight reports only fixed readiness labels and issue codes such as
`missing-host`, `missing-credential`, `missing-stimulus-command`, and
`invalid-port`. It does not print host identity, credential values, port value,
or stimulus command text. `--ask-password` is reported as `promptRequested`
without reading from the terminal.

```bash
NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_MAC_PASSWORD='...' \
swift run VNCLiveBenchmark \
  --attempts 3 \
  --full-refresh-samples 2 \
  --stream-shape-samples 30 \
  --stream-shape-duration-seconds 60 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --first-frame-profiles stream-shape-profiles \
  --stream-shape-profiles all \
  --stream-shape-transport both \
  --continuous-update-samples 3
```

For practical optimization PRs, start with the shorter named matrix before an
exhaustive all-profile sweep:

```bash
swift build --product VNCLiveStimulusWindow

NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-core \
  --ask-password \
  --json
```

When the core gate says transport/profile pressure is the likely bottleneck,
run the benchmark-only pixel-format gate before changing the app default:

```bash
NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-pixel-format \
  --ask-password \
  --json
```

This compares full-color and RGB565-in-32 profiles under the same sustained v2
stimulus, pacing, transport, and profile-rotation shape. Treat it as a server
compatibility and pressure-isolation gate only; do not change the app's default
pixel format until live and physical-device artifacts show a clear win.

The live benchmark intentionally redacts the target identity and avoids
emitting framebuffer dimensions, pixel payloads, byte counts, cursor
pixels, and raw error descriptions. The stream-shape probe emits
aggregate FPS (all updates and content updates separately), update-latency,
dirty-rectangle-count, dirty-area permille, changed-pixel permille, and
renderer upload strategy summaries only. Schema v19 also emits aggregate
receive-path timing summaries (`receive total`, `network read`, and
`client processing` ms) so hot-device investigations can separate socket wait
from local decode/dispatch pressure without exposing raw samples. Schema v20
adds actual safe encoding-mix counts so requested profiles can be compared with
what the server actually sent. It also emits fixed-threshold tail
buckets for updates at or above 250 ms / 1000 ms, including only aggregate
slow-frame counts and whether those slow frames were content, full-dirty, or
full-upload classified. Schema v21 adds
`--stream-shape-client-pressure off|app`; `app` mirrors the runtime viewer's
repeated lagging client-processing content-frame trigger and temporarily applies
the same power-saver pacing floor during stream-shape probes, while reporting
only the fixed mode label and threshold constants. Schema v22 adds aggregate
`adaptiveClientPressurePacingSamples` and
`adaptiveClientPressurePacingPermille` fields to each stream-shape summary so
heat/FPS comparisons can tell whether the adaptive client-pressure floor
actually affected update pacing. Schema v28 adds the app-mirrored single
very-slow local-work threshold used to enter adaptive client-pressure pacing
after one 1000 ms-class decode/apply spike. Schema v29 splits the recovery
windows so a single very-slow spike reports
`streamShapeClientPressureVerySlowRecoveryUpdateCount`, while repeated lag or
full-upload pressure still reports `streamShapeClientPressureRecoveryUpdateCount`.
Schema v30 adds optional `tailLatency` ordinal aggregates for the first slow and
very-slow update/content update, so cold-start tails can be distinguished from
later sustained tails without exporting raw per-frame samples.
Schema v31 adds optional aggregate ZRLE decode phase summaries
(`zrleInflateLatency` and `zrleTileApplyLatency`) for stream-shape samples whose
actual encoding mix includes ZRLE. These fields split local zlib inflate from
local tile parsing/framebuffer apply work without exporting dimensions,
coordinates, pixels, byte counts, raw payloads, or per-frame sample arrays.
Schema v32 adds `--stream-shape-stimulus off|external-command`,
`streamShapeStimulusMode`, and `streamShapeStimulusWarmupSeconds` so live
duration runs can measure content FPS against repeatable screen motion. In
`external-command` mode the benchmark launches `NARU_LIVE_STIMULUS_COMMAND`
once per stream-shape probe, starts the child with a minimal launch environment
plus duration/profile/transport hints, strips VNC target environment variables,
and does not emit the command text or command output.
Schema v33 adds `--stream-shape-profile-iterations N`,
`--stream-shape-profile-order fixed|rotate`, fixed per-probe iteration/order
ordinals, `streamShapeProfileAggregates`, and
`streamShapeOrderNeutralRecommendation` so default-changing benchmark runs can
rotate candidates and score aggregates instead of overfitting to first-profile
cold-start behavior.
Schema v34 adds `--stream-shape-preflight-frames N`, which consumes a bounded
number of hidden incremental frames after the stream-shape first frame and
before measured samples. Use it only for warm-up/preflight experiments and keep
the production app default unchanged until a physical iPhone run confirms the
hand-feel trade-off.
Schema v35 adds `--stream-shape-practical-target
iphone-practical-baseline-v1|iphone-sustained-usability-v2` and makes
`iphone-sustained-usability-v2` the default CLI target for new streaming work.
The v2 target keeps the 8 fps content-FPS floor, adds an average-update band
of 180 ms pass / 250 ms fail, tightens post-warm-up p95 to 350 ms pass /
500 ms fail, expects 0 permille renderer full-upload pressure, and still
requires a physical iPhone 10 minute hand-feel/thermal pass before production
defaults change. Use v1 only for legacy artifact comparison.
Schema v36 adds stream-shape hit-rate diagnostics:
`attemptedSamples`, `receivedSamplePermille`, `unansweredSamplePermille`,
`contentSamplePermille`, `emptyResponsePermille`, and
`contentResponsePermille`, plus matching per-profile aggregate/recommendation
fields. Use these aggregate ratios to distinguish low content FPS caused by
unanswered sample waits or low content hit-rate from low FPS caused by slow
but consistently content-bearing updates. Per-profile aggregate permille fields
are run-level means so rotated benchmark iterations have equal weight when
duration-capped attempts vary. These fields must remain counts and permille
ratios only; do not add per-frame request arrays, timestamps, dimensions,
coordinates, pixels, cursor pixels, byte counts, raw payloads, raw errors, or
target identity.
Schema v37 adds `streamShapeProfileGates`, a per-profile/transport gate summary
for multi-iteration sustained-stream runs. Each gate reports only the fixed
target name, fixed verdict, fixed issue-code union, aggregate
pass/warning/fail/disabled run counts, total run count, and aggregate hit-rate
permille means. Use it as the first screen for larger default-change decisions:
only profiles whose gate is `pass` or intentionally accepted `warning` should
graduate to physical iPhone hand-feel/thermal comparison. Do not add profile
host identity, dimensions, coordinates, pixels, cursor pixels, byte counts, raw
FPS, raw timings, raw samples, raw payloads, raw errors, external command text,
or command output to profile gates.
For new practical-usability PRs, use the profile gate plus
`iphone-sustained-usability-v2` as the default decision surface. A production
streaming default should not change until a redacted controlled-stimulus
run has an explicit gate judgment and a physical iPhone 10 minute
hand-feel/thermal pass confirms no `.serious` or `.critical` thermal state.
The app stream startup preflight gate is separate from the benchmark-only v34
flag: the runtime policy is injectable and off by default, may consume at most
one hidden incremental update after the first visible frame, and must not be
enabled by default until the physical iPhone gate confirms that it improves
hand feel without stale startup perception or thermal regressions.
The interaction v2 preflight keeps the same sustained target but treats local
hand-feel as a first-class gate: zoomed trackpad cursor-follow must preserve
finger-paced visible cursor travel, direct viewport motion must stay on the
UIKit/Core Animation hot path, SwiftUI/PiP viewport mirroring must not run per
touch sample, and marked-text Compose Send must use the bounded stabilization
window before paste dispatch.
Diagnostic JSON v24 adds safe Compose Send preparation fields for T390:
`latestComposeSendPreparationMode`,
`latestComposeSendPreparationSnapshotCount`, and
`latestComposeSendPreparationDurationBucket`. Use these only as coarse
pre-paste input-path signals; do not add raw draft text, marked text, or raw
timings to benchmark artifacts.
Diagnostic JSON v25 adds top-level `sustainedSessionAssessment` for
`iphone-sustained-usability-v2`, with only fixed verdict and issue-code labels.
The app may use exact FPS in memory to choose those labels, but artifacts must
not include raw FPS, raw timings, host identity, dimensions, coordinates, pixels,
byte counts, draft text, or IME state.
Diagnostic JSON v26 adds app-side startup preflight experiment fields:
top-level `viewerStartupPreflightMode` plus safe stream-performance
`startupPreflightRequestedHiddenFrameCount`,
`startupPreflightConsumedHiddenFrameCount`, and `startupPreflightOutcome`.
Use these only to compare disabled vs one-hidden-frame physical-device runs;
do not include hidden frame contents, hidden frame timings, raw errors, host
identity, dimensions, coordinates, pixels, byte counts, raw FPS, draft text,
marked text, or IME state in artifacts.
`--environment-preflight` is a separate benchmark setup check. It emits schema
v6 readiness labels before connecting or prompting for a password, including
fixed `setupActionLabels` such as `set-naru-live-mac-host`,
`set-naru-live-stimulus-command`,
`grant-helper-video-app-screen-recording-permission`,
`inspect-helper-video-capability`, and `run-live-gate`. It is
meant to explain why a live profile gate could not be attempted without
printing configured target values.
`--helper-video-probe-only` is a separate helper setup check. It does not read
live VNC target credentials and should be used after helper install or Screen
Recording permission changes before running a full live comparison.
Schema v38 adds `--stream-shape-gate-preset none|sustained-v2-core` plus
`streamShapeGatePreset` in benchmark reports. Schema v39 adds
`sustained-v2-pixel-format` and `--stream-shape-profiles
pixel-format-isolation`. The sustained v2 core preset is the standard
large-unit live gate: controlled stimulus, core matrix profiles, both
transports, five rotated iterations, app client-pressure pacing,
steady-stream viewport mode, ten second duration, zero hidden stream-shape
preflight frames, and the `iphone-sustained-usability-v2` target. The
pixel-format preset keeps that same gate shape but swaps in full-color/RGB565-in-32
profile pairs. Use explicit
stream-shape options without the preset for custom experiments.
`sustained-v2-request-response` keeps the core matrix gate shape but measures
request/response only, so request/response candidates can be compared after
ContinuousUpdates has already been routed to support inspection.
`sustained-v2-zrle-isolation` keeps that same request/response-only shape but
uses `zrle-isolation` to compare the current default against pure ZRLE
compression 0 and cursor/ExtendedClipboard extension variants. Schema v45 adds
this fixed preset label. `sustained-v2-zrle-zero-delay` keeps the ZRLE
isolation shape but sets `streamShapeFrameIntervalSeconds=0` as a benchmark-only
request-cadence pressure test. Schema v46 adds this fixed preset label and makes
transport/cadence diagnosis route receive-path-majority mixed failures to
`tuneTransportCadence`. Schema v47 adds top-level
`streamShapeRequestCadenceHealth`, derived from request/response aggregates and
gates, so reports can distinguish high content hit with p95 tail from
unanswered waits or empty responses before changing app defaults. Schema v48
adds fixed `streamShapePacingWindows` labels so request pacing windows can be
compared without mixing them into one profile aggregate. For
request/response-only presets the standalone ContinuousUpdates probe is also
skipped:
`continuousUpdateSamples` is 0 and `continuousUpdatesProbe.status` is
`not-tested`.
The sustained v2 presets are steady-stream gates: they keep
`streamShapeViewportInteractionMode=off` so the 8fps controlled-stimulus target
is not capped by the app's active viewport-interaction 4 Hz pacing floor. Use a
custom non-preset command with `--stream-shape-viewport-interaction app` only
when measuring active zoom/pan stream pressure; physical iPhone diagnostics
remain the promotion gate for hand-feel.
Schema v40 extends stream-shape `practicalAssessment` with
`primaryIssueCode`, `primaryConstraint`, and `recommendedNextProbe`, using the
same fixed sustained-session triage catalog as diagnostic JSON v28. Treat these
fields as the benchmark-side decision surface for the next large unit:
content/receive constraints route to sustained profile or transport cadence
gates, client-decode constraints route to encoding-profile comparison,
renderer-upload constraints route to local render pipeline inspection, adaptive
pacing constraints route to pacing comparison, and sample-size constraints
route to longer physical-device collection. Do not add host identity,
dimensions, coordinates, pixels, cursor pixels, byte counts, raw FPS, raw
timings, TCP/RFB errors, draft text, marked text, or IME state to benchmark
artifacts.
Schema v41 lifts the same triage surface to `streamShapeProfileGates` and adds
top-level `streamShapeOptimizationDecision` so a whole benchmark report chooses
one next large unit before individual profile recommendations are considered.
The decision reports fixed gate counts, fixed triage label counts, a primary
issue, a primary constraint, and a recommended next probe. Use it as the first
report-level routing signal; the existing profile recommendations remain the
profile-choice signal after the blocking constraint is understood. Its
`blockedGateCount` is a derived `warningGateCount + failGateCount` value, not a
separately trusted decoded input.
Schema v42 adds safe `failureLabelCounts` to `streamShapeProfileGates` and
`streamShapeOptimizationDecision`. These counts lift existing fixed benchmark
failure labels from individual stream-shape probe summaries into the decision
surface, so repeated ContinuousUpdates or request/response failures can be
triaged without opening raw JSON. Do not add raw TCP/RFB errors, host identity,
dimensions, coordinates, pixels, cursor pixels, byte counts, payloads, command
text, command output, draft text, marked text, or IME state to these counts.
Schema v43 adds top-level `streamShapeTransportCadenceDiagnosis` with fixed
request-response and ContinuousUpdates status labels, aggregate blocked/total
gate counts, per-transport constraint/failure-label counts, a recommended
transport label, and a fixed next-action label. Use it after
`streamShapeOptimizationDecision.recommendedNextProbe=inspectServerTransportCadence`
to decide whether the next large unit should inspect ContinuousUpdates
connection/receive behavior, tune transport cadence, compare
request-response encoding profiles, or move to a physical-device sustained
gate. Do not add raw timings, raw TCP/RFB errors, host identity, dimensions,
coordinates, pixels, cursor pixels, byte counts, raw payloads, command text,
command output, draft text, marked text, or IME state to this diagnosis.
Schema v44 adds `streamShapeStimulusFrameIntervalSeconds` and
`streamShapeStimulusExpectedFramesPerSecond`. The sustained v2 presets pass the
same configured 12 Hz cadence to `VNCLiveStimulusWindow` through
`NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS`. Treat the v2 content-FPS target as
8fps against that known stimulus: if expected stimulus FPS is 12 but measured
content FPS stays near 2, route the next unit to server/transport/profile
cadence inspection rather than blaming the stimulus helper or renderer upload
alone. Do not emit stimulus command text, command output, host identity,
coordinates, pixels, cursor pixels, byte counts, raw timings, draft text,
marked text, or IME state with these fields.
Diagnostic collection schema v27 adds the app-side
`viewerStreamEncodingMode` fixed label so physical iPhone runs can be matched
to the benchmark candidate selected in app settings without exporting raw
transport, pixel, coordinate, timing, draft, or IME state.
Diagnostic collection schema v28 extends `sustainedSessionAssessment` with
`primaryIssueCode`, `primaryConstraint`, and `recommendedNextProbe`. Treat this
as the first triage surface for physical iPhone reports: thermal issues route
to power-saver/thermal passes, viewport issues route to interaction traces,
local decode/render issues route to profile or render-pipeline gates, and
Compose issues route to helper/clipboard route diagnostics. The fields are
fixed catalog labels derived from existing safe issue codes only; do not add
raw FPS, raw timings, host identity, dimensions, coordinates, pixels, cursor
pixels, byte counts, raw payloads, draft text, marked text, or IME state.
Diagnostic collection schema v29 adds `physicalGateVerdict`, which is `pass`
only when no sustained-session issue codes are present and `blocked` otherwise.
Use it as the strict physical-device promotion signal; keep
`primaryConstraint` and `recommendedNextProbe` for choosing the next large work
unit.
By default, stream-shape uses the app's `local-low-latency` profile; pass
`--stream-shape-profiles core-matrix` for the standard practical candidate
set (`local-low-latency`, `zrle-compression-0`, `tight-first`, and
`adaptive-good-full`) before deciding whether the next larger unit should
change request cadence, transport, encoding profile, or server compatibility.
Pass `--stream-shape-profiles zrle-isolation` to compare the current default
against pure ZRLE compression 0 plus cursor/ExtendedClipboard extension
variants under the same dynamic stimulus.
Pass `--stream-shape-profiles pixel-format-isolation` to compare benchmark-only
full-color/RGB565-in-32 pairs without changing the app's normal connection path.
Example:
`--stream-shape-gate-preset sustained-v2-zrle-isolation`.
For zero post-content request delay comparison, use:
`--stream-shape-gate-preset sustained-v2-zrle-zero-delay`.
For the fixed request pacing window comparison, use:
`--stream-shape-gate-preset sustained-v2-zrle-pacing-sweep`.
The preset already applies
`--stream-shape-profile-iterations 5 --stream-shape-profile-order rotate` so
each selected candidate leads one iteration. The pacing sweep intentionally
holds the profile at `zrle-compression-0-clipboard` and rotates fixed pacing
windows instead of the full `zrle-isolation` profile list. Use custom commands
only when intentionally changing that shape.
Schema v49 adds safe phase-budget summaries. Read
`phase dominant/slow-dominant` before picking the next large optimization lane:
`request-loop` or `network-read` means inspect update-wait/request-response
timing, while `client-processing` means compare encoding/decode pressure before
changing pacing again. The budget is aggregate-only and must not export raw
per-sample timings, host identity, dimensions, coordinates, pixels, byte counts,
cursor pixels, raw errors, stimulus command text, draft text, marked text, or
IME state. The first v49 live artifact is
`2026-06-06-request-update-phase-budget-summary.md`; it routes the next large
unit to request/response update-wait and network-read tail inspection.
Schema v50 splits the v49 `network-read` bucket into first-byte wait and
payload-read subphases. Read `network-read subphase dominant/slow-dominant` and
`network-read split permille first-byte/payload` before changing socket payload
or decoder work: first-byte dominance means the current blocker is server/update
wait, while payload-read dominance would route to socket buffering, byte volume,
or payload-copy work. The first v50 live artifact is
`2026-06-06-first-byte-wait-split-summary.md`; it shows the current localhost
macOS Screen Sharing tail is almost entirely first-byte wait.
Schema v51 adds fixed `streamShapeRequestRegions` labels to compare incremental
FramebufferUpdateRequest regions without exporting coordinates or dimensions.
The first v51 live artifact is
`2026-06-06-request-region-sweep-summary.md`; it shows full-screen incremental
requests remained the only usable candidate while static `center-half` and
`center-third` requests starved with incremental read timeouts. Treat this as a
guardrail: request-region optimization must be viewport-aware and carry a
full-request fallback or heartbeat before any production default changes.
Schema v52 adds the benchmark-only
`--stream-shape-gate-preset sustained-v2-zrle-viewport-region` shape. It keeps
the same ZRLE request/response controlled-stimulus gate but compares `full`
against fixed phone-portrait viewport-aware labels, including a heartbeat
candidate. Reports still contain only labels and aggregate metrics; actual
request rectangles remain unreported. The first v52 live artifact is
`2026-06-06-viewport-region-foundation-summary.md`; it keeps `full` as the only
stable candidate and routes the next larger unit to request/response transport
cadence plus region-timeout recovery before any app default changes.
Schema v53 adds `requestRegionAreaPermille`, a traffic-pressure proxy for
poor-network promotion work. It reports only the requested framebuffer area as a
0...1000 ratio relative to the full framebuffer (`full` = 1000); it does not
emit byte counts, dimensions, coordinates, pixels, or payloads. Treat this
metric together with usable runs, hit-rate, p95 update tail, failure labels, and
full fallback/heartbeat behavior: area savings without stability is not a
production default candidate.
Schema v54 keeps the same redacted report shape but changes request/response
region recovery semantics: a zero-byte incremental request timeout with an
existing framebuffer is an idle frame, and viewport-region probes can issue
their full fallback request on the same socket. Non-incremental request
timeouts and partial-message timeouts remain fatal. Use v54 when comparing
poor-network traffic candidates so `requestRegionAreaPermille` is judged
against stability rather than reconnect artifacts.
Schema v55 adds `networkCondition`, a fixed-label live benchmark conditioning
profile. Pass `--network-condition wan-latency` to inject benchmark-local
latency without a throughput cap, or `--network-condition constrained-cellular`
to add higher latency, smaller chunks, and a fixed throughput cap through a
local TCP proxy. Reports emit only the fixed profile label; they do not emit
proxy ports, upstream hosts, byte counters, dimensions, coordinates, pixels, or
payloads. Use v55 for poor-network traffic comparisons before promoting any
request-region, encoding, pacing, or pixel-format default.
Schema v56 adds `iphone-poor-network-traffic-v1` and the benchmark-only
`--stream-shape-gate-preset sustained-v2-constrained-cellular-bootstrap`.
The preset fixes `networkCondition` to `constrained-cellular`, uses
request/response-only `pixel-format-isolation` profiles over the
`viewport-phone-portrait` incremental request label, and emits fixed
`first-frame-*` / `request-region-area-*` gate issue codes. Use it to separate
"can collect steady-state samples" from "starts fast enough for poor-network
iPhone use" before changing defaults. The first v56 live artifact is
`2026-06-06-constrained-cellular-bootstrap-gate-summary.md`; it shows RGB565
survives startup where full-color times out, but still fails the 20 s startup
target, routing the next large unit to first-visible-region bootstrap work.
Schema v57 adds `streamShapeFirstFrameRequestMode` and
`--stream-shape-first-frame-request full|match-request-region`. It also adds
`--stream-shape-gate-preset
sustained-v2-constrained-cellular-visible-startup`, which keeps the v56
constrained-cellular shape but requests the fixed visible phone viewport region
for the first non-incremental frame. Reports emit only the fixed first-frame
request mode label plus existing aggregate metrics; they do not emit
coordinates, dimensions, byte counts, pixels, or payloads. Use v57 to compare
poor-network startup traffic pressure against the v56 full-frame baseline
before any production request-region default. The first v57 live artifact is
`2026-06-06-constrained-cellular-visible-startup-summary.md`; it improves
RGB565 startup by roughly 8.6 seconds but remains below the poor-network gate.
Schema v58 adds `--stream-shape-first-frame-request visible-core`,
`firstFrameRequestAreaPermille`, and `--stream-shape-gate-preset
sustained-v2-constrained-cellular-visible-core-startup`. The new preset keeps
the constrained-cellular v57 shape but removes the startup-only visible-region
margin for the first non-incremental frame while sustained requests keep the
normal viewport margin and fallback behavior. Poor-network traffic gates now
judge the larger of sustained request area and first-frame request area, and
reports still emit only fixed labels and framebuffer-relative permille ratios,
never coordinates, dimensions, byte counts, pixels, or payloads.
Schema v59 adds `firstFrameReceiveTiming` and aggregate first-frame receive
timing fields so startup can be separated into first-byte wait, payload read,
and client processing without exposing frame contents. The first v59 live
artifact is
`2026-06-06-constrained-cellular-visible-core-startup-timing-summary.md`; it
shows RGB565 visible-core startup still failing just above 20 s, with roughly
95% of first-frame network read time spent in payload read. Sustained samples
from the same run remain first-byte-wait dominated, so startup payload pressure
and steady update-wait cadence should be treated as separate optimization
tracks.
Schema v60 adds `--stream-shape-first-frame-request visible-focus` and
`--stream-shape-gate-preset
sustained-v2-constrained-cellular-visible-focus-startup`. This is still a
benchmark-only startup traffic probe: it requests a smaller fixed central focus
area for the first non-incremental frame, then keeps sustained incremental
requests on the normal viewport region and fallback policy. Reports continue to
emit only fixed labels, first-frame request-area permille, and aggregate
receive timing; they do not emit dimensions, coordinates, byte counts, pixels,
or payloads. Use v60 to test whether first-useful-paint can clear the poor
network startup gate before considering a staged startup design. The first v60
live artifact is
`2026-06-06-constrained-cellular-visible-focus-startup-summary.md`; it shows
RGB565 startup dropping to roughly 16.3-16.4 s while the sustained stream still
needs update-wait work.
Schema v61 keeps the same redacted report shape and promotes sustained
first-byte wait / payload-read pressure into the poor-network traffic gate.
This keeps request-area savings from being mistaken for practical usability:
payload-read pressure routes to encoding/traffic comparison, while first-byte
wait routes to update-wait timing inspection. The first v61 live artifact is
`2026-06-06-constrained-cellular-sustained-traffic-wait-summary.md`; it keeps
the RGB565 visible-focus startup win, but classifies the usable sustained
samples as `first-byte-wait-warning` rather than payload-read pressure.
The app low-traffic follow-up adds the `app-low-traffic` profile selection and
`--stream-shape-gate-preset
sustained-v2-constrained-cellular-app-low-traffic`. This preset originally
narrowed the matrix to the app's fixed `zrle-compression-0-rgb565` opt-in
profile so physical iPhone and live CLI runs could judge the same traffic
candidate without full-color startup failures dominating the report. After the
visible-glance startup policy landed, the same preset compares both app-side
RGB565 low-traffic candidates: `local-low-latency-rgb565` and
`zrle-compression-0-rgb565`. It remains an opt-in candidate gate: production
defaults still require sustained and poor-network benchmark evidence plus the
physical iPhone hand-feel/thermal/Compose gate before promotion.
Schema v62 keeps that app low-traffic shape but adds startup payload-read
pressure to the poor-network profile gate. A run can now fail with
`first-frame-payload-read-failed` even when the first-frame request area is
small, which routes the next action to encoding/traffic comparison instead of
renderer-upload work. The first v62 live artifact is
`2026-06-06-startup-payload-traffic-gate-summary.md`; it records a redacted
local VNC app-low-traffic run where first-frame request area was 192 permille,
but about 14.2 s of payload read still made startup fail the poor-network
traffic target.
Schema v63 adds the fixed `visible-glance` first-frame request mode for
startup-only first-useful-paint experiments. It scales the visible core down
before the first non-incremental request, then returns sustained incremental
requests to the normal viewport-aware region. The app-candidate live artifact is
`2026-06-06-app-low-traffic-visible-glance-live-gate-summary.md`; it records the
fixed `zrle-compression-0-rgb565` profile at 108 permille first-frame request
area, about 10.4 s first-frame payload read, and 4/4 sustained content samples.
The gate still fails, so this is a startup improvement and not a default
promotion.
The next app-candidate live artifact is
`2026-06-06-app-low-traffic-rgb565-profile-comparison-summary.md`; with the
same visible-glance startup area, it shows `local-low-latency-rgb565` keeping
4/4 sustained content samples, lower average/p95 update latency, and 0 permille
renderer full-upload pressure compared with `zrle-compression-0-rgb565`. The
poor-network gate still fails on first-frame payload read, so the practical
next step stays startup traffic/cadence work rather than promoting the profile
as the default.
A follow-up scale-tuning artifact is
`2026-06-06-app-low-traffic-glance-scale-tuning-summary.md`; it tightens the
visible-glance startup scale from 0.60 to 0.45. The first-frame request area
drops from 108 to 61 permille and first-frame payload read drops to about
8.1-8.2 s while both app RGB565 candidates keep 4/4 sustained content samples
and 0 permille renderer full-upload pressure. The poor-network gate still
fails on first-frame payload-read share, so this is a first-useful-paint
improvement, not the end of startup traffic work.
Schema v64 adds
`--stream-shape-first-frame-visible-glance-scale SCALE`, a benchmark-only
override for the visible-glance first-frame scale. Reports emit only
`streamShapeFirstFrameVisibleGlanceScalePermille`, not coordinates,
dimensions, bytes, or pixels. The scale-sweep artifact is
`2026-06-06-app-low-traffic-glance-scale-sweep-summary.md`; it compares 0.35
and 0.25 under the app-low-traffic constrained-cellular preset. In that run,
0.25 reduced first-frame request area to 19 permille and payload read to about
5.1 s while keeping both app RGB565 candidates at 4/4 sustained content
samples and 0 permille renderer full-upload pressure. Product default
promotion is intentionally deferred until device visual inspection proves the
smaller first-useful-paint patch is recognizable.
Schema v65 adds a synthetic first-frame visual audit for `visible-glance`
reports. The audit emits only a fixed `synthetic-terminal-grid` model label,
axis/area coverage permille values, omitted-area permille, fixed risk label,
and a `visualCheckRequired` boolean. It never emits live pixels, coordinates,
dimensions, byte counts, host identity, or text. The visual-audit artifact is
`2026-06-06-app-low-traffic-visual-audit-summary.md`; it records that the 0.25
scale covers only 250 permille of each visible-core axis and 63 permille of the
visible-core area. The same v65 live run improved the app-low-traffic
poor-network verdict to `warning`, with about 4.9 s first-frame payload read,
4/4 sustained content samples, and 0 permille renderer full-upload pressure for
both app RGB565 candidates. That makes 0.25 the strongest startup traffic
candidate so far, but it remains a `glance-only` visual-risk candidate requiring
real iPhone visual inspection before any product-default promotion.
The app follow-up artifact is
`2026-06-06-startup-glance-scale-setting-summary.md`. It keeps the product
default at 0.45 but adds an inactive-session low-traffic RGB565 toggle for
0.45/0.35/0.25 startup glance candidates, plus diagnostic schema v30
`viewerStartupGlanceScaleMode` safe labels. This lets physical iPhone runs
compare visual recognizability without rebuilding or exporting live pixels,
dimensions, coordinates, bytes, host identity, or text.
When `--stream-shape-transport both` is used with rotate mode, transport order
also rotates by iteration so request/response and ContinuousUpdates do not
always run in the same relative slot.
Treat the rotated schema v33 run as the do-not-regress gate before larger
streaming changes: the selected order-neutral profile should keep 0 permille
renderer full-upload pressure, stay at or below 250 ms average update, 500 ms
max p95 update, and 30 ms max client-processing p95, and avoid unsafe diagnostic
fields. The practical-use target is higher: controlled-stimulus content FPS at
8 fps or better in the steady-stream gate, 180 ms average update or better,
p95 below 350 ms after warm-up, 0 permille renderer full-upload pressure,
immediate local zoom/pan transforms in the physical gate, deterministic Compose
route diagnostics, and a physical iPhone 10 minute session without `.serious`
or `.critical` thermal state.
The current interaction baseline keeps visible pinch/pan/trackpad movement on
the UIKit/Core Animation path, defers SwiftUI/PiP viewport mirroring until the
gesture settles, keeps zoomed trackpad cursor travel finger-paced while
follow-pan is coupled in, and uses a bounded Compose stabilization window for
active or recently committed Korean/CJK marked text. Treat regressions against
those invariants as interaction-gate failures before changing stream defaults.
Pass
`--stream-shape-profiles all` when comparing whether Tight/ZRLE/adaptive
profiles actually improve sustained interaction on the current server.
For targeted longer runs after an all-profile sweep, pass a comma-separated
subset such as `--stream-shape-profiles tight-first,zrle-compression-0,adaptive-good-full`
so the benchmark spends time only on the current candidates.
Use `zrle-compression-0-cursor`, `zrle-compression-0-clipboard`, and
`zrle-compression-0-cursor-clipboard` when isolating whether the server cursor
or ExtendedClipboard pseudo-encoding request changes sustained tail behavior.
Use `--stream-shape-duration-seconds` for sustained thermal/FPS runs; pair it
with `--stream-shape-samples 0` when the run should stop only by duration
rather than by a sample cap. Duration-capped runs also cap each in-flight
update wait and post-update pacing delay to the remaining duration, reducing
tail overshoot during long thermal runs.
The default `--stream-shape-empty-backoff app` mode mirrors the app's
sustained empty-update backoff so static-screen benchmark pacing matches
the runtime stream loop; use `none` only when comparing against legacy
fixed idle polling.
The app's default active content-request interval is 60 Hz-class
`1/60`, while static/empty incremental replies still use the separate
idle delay and adaptive empty-update backoff.
Use `--stream-shape-client-pressure app` for sustained heat/FPS comparisons
after a baseline run with the default `off` mode, especially when receive timing
shows client-processing tails rather than mostly network/server wait. App mode
mirrors the runtime severe 80 ms / 3 content-frame trigger and the sustained
moderate 34 ms / 8 content-frame trigger before temporarily applying the
power-saver pacing floor.
Use `--stream-shape-power-mode low-power` to mirror the app's Low Power
Mode floors: active content requests are capped at 30 Hz and empty
incremental polling has a 125 ms minimum unless the explicit configured
interval is zero for a deterministic test run.
Use `--stream-shape-transport both` when comparing request/response
polling against the ContinuousUpdates/Fence overlay before changing the
production transport gate.
ContinuousUpdates probes are only treated as that transport after the active
RFB session observes server confirmation. If confirmation never arrives, schema
v43 reports the fixed safe label
`stream-continuous-updates-continuous-updates-not-confirmed` and keeps
request/response as the usable fallback candidate.
In `both` mode, the top-level `streamShapeProbe` remains the first
selected profile/transport as a compatibility summary; use
`streamShapeProfileProbes` for the full profile-by-transport matrix.
For longer stream-shape-only runs, pass `--first-frame-profiles
stream-shape-profiles` to benchmark first-frame latency only for the
same profiles being stream-shaped, or `--first-frame-profiles none` to
skip the first-frame/full-refresh sweep entirely.
The bounded candidate-stability artifact is
`2026-06-07-tight-first-rgb565-candidate-summary.md`; it adds benchmark-only
`tight-first-rgb565` to the repeated `tight-first` /
`adaptive-good-full` comparison. The live run keeps `tight-first` as the
order-neutral recommendation and improves it to warning-only, while
`tight-first-rgb565` fails one of three runs with a worse update tail
(107 ms average, 473 ms max p95) despite 0 permille renderer full-upload
pressure. Do not promote the RGB565 Tight variant; the next VNC optimization
axis is request/response cadence and server first-byte wait.
The cursor follow-up artifact is
`2026-06-07-tight-first-cursor-candidate-summary.md`; it adds benchmark-only
`tight-first-cursor` and `tight-first-cursor-clipboard`, then runs a bounded
`tight-first` vs `tight-first-cursor` comparison for the trackpad real-cursor
path. In the launchctl-backed live run, `tight-first-cursor` becomes the
order-neutral recommendation with 6/6 content samples, 22.47 content FPS,
24 ms average update, 32 ms max p95 update, 1 ms max client-processing p95,
and 0 permille renderer full-upload pressure. The clipboard variant failed an
ad hoc live check with 146 ms client-processing p95, so keep clipboard separate
from the next Tight app candidate.
The sustained depth artifact is
`2026-06-07-tight-first-cursor-depth-sweep-summary.md`; it runs fixed
`tight-first-cursor` at request pipeline depths 1, 2, and 3 for 12 samples /
10 seconds each. Depth 1 remains the product candidate with 11/12 content
samples, 9.01 content FPS, 78 ms average update, and 2 ms client-processing
p95. Depth 2 still warns and has lower content cadence; depth 3 fails from
128 ms client-processing p95. Keep product request pipeline depth at 1.
The app opt-in artifact is
`2026-06-07-tight-first-cursor-app-mode-summary.md`; it exposes
`tight-first-cursor` as a user-selectable stream mode while keeping
`standard` as the default. The app mode uses Tight + Cursor + quality 8 +
compression 1, with no RGB565, no ExtendedClipboard, and request pipeline
depth 1. Use it for physical iPhone trackpad/real-cursor verification before
any default promotion.
The trackpad live publish artifact is
`2026-06-07-trackpad-live-viewport-publish-summary.md`; it keeps direct
pinch/pan viewport-state publication deferred until gesture end, but lets
zoomed trackpad cursor-follow publish pending viewport state on a bounded
display link while `liveRemoteFrames` is active. This should reduce the
half-step feel between local panning and remote cursor/text echo without
promoting a new traffic profile.
The physical-freeze mitigation artifact is
`2026-06-07-ui-frame-processing-unblock-summary.md`; it records the first
MainActor split after physical iPhone testing showed that a real VNC
connection could freeze gestures and keyboard input. The patch moves the VNC
frame loop off MainActor, stops foreground frames from feeding PiP
sample-buffer conversion, detaches preview-thumbnail sampling, and makes the
helper-video runner non-MainActor with an explicit main-actor renderer box.
The frame-application backlog artifact is
`2026-06-07-frame-application-backlog-coalescing-summary.md`; it bounds the
post-receive MainActor apply queue so a busy iPhone UI keeps the initial
diagnostic frame, latest framebuffer, and latest server cursor instead of
replaying stale visual states after gestures or keyboard input have already
fallen behind.
