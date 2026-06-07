#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/run-naru-live-benchmark.sh MODE [-- extra VNCLiveBenchmark args]

Runs common live benchmark and helper-video setup checks by importing sensitive
values from launchctl environment variables into the child process only.

Modes:
  preflight                Redacted live environment and helper capture readiness.
  helper-synthetic-probe   Helper-video probe-only run with external synthetic H.264.
  helper-sustained-synthetic-probe Helper-video sustained external synthetic H.264 run.
  helper-screen-probe      Helper-video probe-only run with external ScreenCaptureKit.
  helper-readiness-sweep   Safe helper capability/preflight/synthetic/screen sweep.
  helper-dev-app-setup     Install dev helper app, set launchctl, request Screen Recording.
  helper-screen-app-bootstrap-benchmark ScreenCaptureKit app bootstrap/decode smoke.
  helper-video-live-gate Screen Recording watch + true helper-video gate chain.
  helper-video-live-gate-self-test Fast regression for helper-video live gate labels.
  short-live-comparison    Short constrained-cellular VNC + synthetic helper-video run.
  glance-scale-sweep       Short 0.45/0.35/0.25 startup glance candidate sweep.
  glance-025-duration-probe Duration-only 0.25 startup glance local RGB565 probe.
  glance-025-profile-sweep Duration-only 0.25 startup glance app profile sweep.
  glance-025-10fps-duration-probe 10fps target probe for the 0.25 local RGB565 candidate.
  remote-desktop-10fps-profile-cadence-sweep Compare 10fps VNC profiles for first-byte/server cadence.
  remote-desktop-10fps-server-cadence-probe Compare network/request-region startup axes for server cadence.
  remote-desktop-10fps-transport-cadence-drilldown Compare request-response vs ContinuousUpdates under the 10fps VNC gate.
  remote-desktop-10fps-readiness 10fps VNC gate + helper-video readiness dashboard.
  remote-desktop-readiness-summary-self-test Fast regression for readiness gate summary labels.
  screen-recording-watch Request helper Screen Recording, open Settings, and poll safe capability.
  screen-recording-watch-self-test Fast regression for screen-recording-watch labels.
  request-pipeline-sweep   Short VNC-only constrained-cellular depth 1/2/3 sweep.
  bounded-vnc-profile-sweep Short bounded VNC profile candidate sweep.
  bounded-vnc-profile-drilldown Per-profile bounded VNC candidate drilldown.
  bounded-vnc-candidate-stability Repeat bounded warning-candidate VNC sweep.
  bounded-vnc-tight-cursor-stability Repeat Tight cursor candidate VNC sweep.
  bounded-vnc-tight-cursor-depth-sweep Long Tight cursor depth 1/2/3 sweep.
  physical-device-preflight Safe physical iPhone build/signing readiness labels.
  physical-team-inference-self-test Safe local regression for team inference labels.
  screen-recording-setup   Request helper Screen Recording and open Settings.
  helper-capability        Run the selected helper's safe --video-capability.
  request-screen-recording Run the selected helper's explicit permission request.

Launchctl variables used when present:
  NARU_HELPER_EXECUTABLE
  NARU_LIVE_MAC_HOST
  NARU_LIVE_MAC_PORT
  NARU_LIVE_MAC_PASSWORD
  NARU_LIVE_STIMULUS_COMMAND
  NARU_PHYSICAL_IOS_DEVICE_ID
  NARU_XCODE_DEVELOPMENT_TEAM
  NARU_HELPER_VIDEO_SUSTAINED_FRAME_COUNT
  NARU_HELPER_DEV_APP_ROOT
  NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip
  NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS
  NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS

The script never prints environment values. It passes through the benchmark's
privacy-safe JSON/report output.
USAGE
}

mode="${1:-}"
case "$mode" in
  --help|-h|"")
    usage
    if [[ -z "$mode" ]]; then
      exit 2
    fi
    exit 0
    ;;
esac
shift || true

extra_arg_count=0
extra_args=()
if (($#)); then
  if [[ "$1" != "--" ]]; then
    printf 'Unexpected argument: %s\n' "$1" >&2
    usage >&2
    exit 2
  fi
  shift
  extra_args=("$@")
  extra_arg_count=$#
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

launchctl_env() {
  local name="$1"
  if ! command -v launchctl >/dev/null 2>&1; then
    return 0
  fi
  launchctl getenv "$name" 2>/dev/null || true
}

import_env() {
  local name="$1"
  local required="$2"
  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    value="$(launchctl_env "$name")"
  fi

  if [[ -z "$value" && "$required" == "required" ]]; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    if command -v launchctl >/dev/null 2>&1; then
      printf 'Set it in launchctl or the current shell before running this mode.\n' >&2
    else
      printf 'launchctl is unavailable; set it in the current shell before running this mode.\n' >&2
    fi
    exit 2
  fi

  if [[ -n "$value" ]]; then
    export "$name=$value"
  fi
}

import_helper_env() {
  import_env NARU_HELPER_EXECUTABLE required
  import_env NARU_HELPER_VIDEO_SUSTAINED_FRAME_COUNT optional
}

import_live_env() {
  import_env NARU_LIVE_MAC_HOST required
  import_env NARU_LIVE_MAC_PASSWORD required
  import_env NARU_LIVE_MAC_PORT optional
  import_env NARU_LIVE_STIMULUS_COMMAND optional
}

import_optional_live_env() {
  import_env NARU_LIVE_MAC_HOST optional
  import_env NARU_LIVE_MAC_PASSWORD optional
  import_env NARU_LIVE_MAC_PORT optional
  import_env NARU_LIVE_STIMULUS_COMMAND optional
}

import_physical_device_env() {
  import_env NARU_PHYSICAL_IOS_DEVICE_ID optional
  import_env NARU_XCODE_DEVELOPMENT_TEAM optional
}

run_benchmark() {
  cd "$repo_root"
  swift run --quiet VNCLiveBenchmark "$@"
}

run_benchmark_with_extra() {
  local args=("$@")
  if ((extra_arg_count)); then
    args+=("${extra_args[@]}")
  fi
  run_benchmark "${args[@]}"
}

run_with_wall_timeout() {
  local seconds="$1"
  shift
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  local timeout_marker
  timeout_marker="$(mktemp "${TMPDIR:-/tmp}/naru-benchmark-timeout.XXXXXX")"

  "$@" &
  local command_pid=$!
  (
    sleep "$seconds"
    if kill -0 "$command_pid" >/dev/null 2>&1; then
      printf '1' >"$timeout_marker"
      pkill -TERM -P "$command_pid" >/dev/null 2>&1 || true
      kill -TERM "$command_pid" >/dev/null 2>&1 || true
    fi
  ) &
  local watchdog_pid=$!

  local status=0
  if wait "$command_pid"; then
    status=0
  else
    status=$?
  fi
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true
  if [[ -s "$timeout_marker" ]]; then
    RUN_WITH_WALL_TIMEOUT_EXPIRED=1
  fi
  rm -f "$timeout_marker"
  return "$status"
}

json_benchmark_or_timeout_failure() {
  local wall_timeout_seconds="$1"
  local phase_file="$2"
  local progress_file="$3"
  shift 3

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-benchmark-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null; then
    cat "$output_file"
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_bounded_sweep_failure benchmarkStep.boundedVNCProfileSweep.timedOut "$phase_file" "$progress_file"
  else
    json_bounded_sweep_failure benchmarkStep.boundedVNCProfileSweep.failed "$phase_file" "$progress_file"
  fi
  rm -f "$output_file"
}

json_benchmark_or_candidate_stability_failure() {
  local wall_timeout_seconds="$1"
  local phase_file="$2"
  local progress_file="$3"
  shift 3

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-candidate-stability-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null; then
    cat "$output_file"
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_bounded_candidate_stability_failure \
      benchmarkStep.boundedVNCCandidateStability.timedOut \
      "$phase_file" \
      "$progress_file"
  else
    json_bounded_candidate_stability_failure \
      benchmarkStep.boundedVNCCandidateStability.failed \
      "$phase_file" \
      "$progress_file"
  fi
  rm -f "$output_file"
}

json_benchmark_or_tight_cursor_stability_failure() {
  local wall_timeout_seconds="$1"
  local phase_file="$2"
  local progress_file="$3"
  shift 3

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-tight-cursor-stability-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null; then
    cat "$output_file"
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_bounded_tight_cursor_stability_failure \
      benchmarkStep.boundedVNCTightCursorStability.timedOut \
      "$phase_file" \
      "$progress_file"
  else
    json_bounded_tight_cursor_stability_failure \
      benchmarkStep.boundedVNCTightCursorStability.failed \
      "$phase_file" \
      "$progress_file"
  fi
  rm -f "$output_file"
}

json_string() {
  local value="$1"
  local escaped
  escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  escaped="${escaped//$'\r'/\\r}"
  escaped="${escaped//$'\t'/\\t}"
  printf '"%s"' "$escaped"
}

json_file_is_valid_or_unchecked() {
  local file="$1"
  [[ -s "$file" ]] || return 1

  if command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null 2>&1
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$file" >/dev/null 2>&1
    return
  fi
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$file" >/dev/null 2>&1
    return
  fi

  return 0
}

write_bounded_sweep_phase() {
  local phase_file="$1"
  local phase_label="$2"
  case "$phase_label" in
    runner-starting|swift-build|benchmark-running)
      printf '%s' "$phase_label" >"$phase_file"
      ;;
    *)
      printf 'unknown' >"$phase_file"
      ;;
  esac
}

bounded_sweep_phase_label() {
  local phase_file="$1"
  local phase_label="runner-starting"
  if [[ -s "$phase_file" ]]; then
    phase_label="$(cat "$phase_file" 2>/dev/null || true)"
  fi
  case "$phase_label" in
    runner-starting|swift-build|benchmark-running)
      printf '%s' "$phase_label"
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

json_bounded_sweep_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-sweep","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_bounded_candidate_stability_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-candidate-stability","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_bounded_tight_cursor_stability_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-tight-cursor-stability","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_bounded_tight_cursor_depth_sweep_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-tight-cursor-depth-sweep","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_glance_scale_sweep_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local scale_permille="$3"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"glance-scale-sweep-sample","scalePermille":%d,"status":"failed","safeFailureCode":' "$scale_permille"
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  printf '}'
}

benchmark_progress_subphase_label() {
  local progress_file="$1"
  local label=""
  if [[ -s "$progress_file" ]]; then
    label="$(awk -F= '$1 == "subphase" { print $2; exit }' "$progress_file" 2>/dev/null || true)"
  fi
  case "$label" in
    benchmark-starting|configuration-loaded|first-frame-profiles|idle-probe|stream-shape-profile|continuous-updates-probe|visual-transport-comparison|report-rendering|benchmark-complete)
      printf '%s' "$label"
      ;;
    "")
      return 1
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

bounded_vnc_profile_label_is_safe() {
  local label="$1"
  case "$label" in
    local-low-latency|local-low-latency-rgb565|tight-first|tight-first-rgb565|tight-first-cursor|tight-first-cursor-clipboard|zrle-compression-0|zrle-compression-0-rgb565|adaptive-good-full)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

benchmark_progress_profile_label() {
  local progress_file="$1"
  local label=""
  if [[ -s "$progress_file" ]]; then
    label="$(awk -F= '$1 == "profileLabel" { print $2; exit }' "$progress_file" 2>/dev/null || true)"
  fi
  if [[ -z "$label" ]]; then
    return 1
  fi
  if bounded_vnc_profile_label_is_safe "$label"; then
    printf '%s' "$label"
  else
    printf 'unknown'
  fi
}

print_benchmark_progress_fields() {
  local progress_file="$1"
  [[ -n "$progress_file" ]] || return

  local subphase_label
  if subphase_label="$(benchmark_progress_subphase_label "$progress_file")"; then
    printf ',"lastBenchmarkSubphaseLabel":'
    json_string "$subphase_label"
  fi

  local profile_label
  if profile_label="$(benchmark_progress_profile_label "$progress_file")"; then
    printf ',"lastBenchmarkProfileLabel":'
    json_string "$profile_label"
  fi
}

bounded_drilldown_profile_label() {
  local profile_label="$1"
  if bounded_vnc_profile_label_is_safe "$profile_label"; then
    printf '%s' "$profile_label"
  else
    printf 'unknown'
  fi
}

json_bounded_drilldown_runner_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-drilldown","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  printf '}\n'
}

json_bounded_drilldown_profile_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local profile_label
  profile_label="$(bounded_drilldown_profile_label "$3")"
  local profile_ordinal="$4"
  local progress_file="${5:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-drilldown-profile","profileLabel":'
  json_string "$profile_label"
  printf ',"profileOrdinal":%d,"status":"failed","safeFailureCode":' "$profile_ordinal"
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}'
}

json_bounded_drilldown_profile_result() {
  local phase_file="$1"
  local progress_file="$2"
  local profile_label
  profile_label="$(bounded_drilldown_profile_label "$3")"
  local profile_ordinal="$4"
  local wall_timeout_seconds="$5"
  shift 5

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-bounded-drilldown-output.XXXXXX")"
  : >"$progress_file"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null && [[ -s "$output_file" ]]; then
    printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-drilldown-profile","profileLabel":'
    json_string "$profile_label"
    printf ',"profileOrdinal":%d,"status":"passed","report":' "$profile_ordinal"
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_bounded_drilldown_profile_failure \
      benchmarkStep.boundedVNCProfileDrilldown.timedOut \
      "$phase_file" \
      "$profile_label" \
      "$profile_ordinal" \
      "$progress_file"
  else
    json_bounded_drilldown_profile_failure \
      benchmarkStep.boundedVNCProfileDrilldown.failed \
      "$phase_file" \
      "$profile_label" \
      "$profile_ordinal" \
      "$progress_file"
  fi
  rm -f "$output_file"
}

json_bounded_tight_cursor_depth_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local depth="$3"
  local progress_file="${4:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"bounded-vnc-tight-cursor-depth","profileLabel":"tight-first-cursor","depth":%d,"status":"failed","safeFailureCode":' "$depth"
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}'
}

json_bounded_tight_cursor_depth_result() {
  local phase_file="$1"
  local progress_file="$2"
  local depth="$3"
  local wall_timeout_seconds="$4"
  shift 4

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-tight-cursor-depth-output.XXXXXX")"
  : >"$progress_file"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null && [[ -s "$output_file" ]]; then
    printf '{"schemaVersion":1,"mode":"bounded-vnc-tight-cursor-depth","profileLabel":"tight-first-cursor","depth":%d,"status":"passed","report":' "$depth"
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_bounded_tight_cursor_depth_failure \
      benchmarkStep.boundedVNCTightCursorDepthSweep.timedOut \
      "$phase_file" \
      "$depth" \
      "$progress_file"
  else
    json_bounded_tight_cursor_depth_failure \
      benchmarkStep.boundedVNCTightCursorDepthSweep.failed \
      "$phase_file" \
      "$depth" \
      "$progress_file"
  fi
  rm -f "$output_file"
}

json_glance_scale_sweep_result() {
  local phase_file="$1"
  local scale="$2"
  local scale_permille="$3"
  local wall_timeout_seconds="$4"
  shift 4

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-scale-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null && [[ -s "$output_file" ]]; then
    printf '{"schemaVersion":1,"mode":"glance-scale-sweep-sample","scalePermille":%d,"scaleLabel":' "$scale_permille"
    json_string "$scale"
    printf ',"status":"passed","report":'
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_glance_scale_sweep_failure \
      benchmarkStep.glanceScaleSweep.timedOut \
      "$phase_file" \
      "$scale_permille"
  else
    json_glance_scale_sweep_failure \
      benchmarkStep.glanceScaleSweep.failed \
      "$phase_file" \
      "$scale_permille"
  fi
  rm -f "$output_file"
}

json_glance_025_duration_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"glance-025-duration-probe","profileLabel":"local-low-latency-rgb565","scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

run_glance_025_duration_probe() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-duration-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-duration-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_glance_025_duration_failure \
        benchmarkStep.glance025DurationProbe.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_glance_025_duration_failure \
        benchmarkStep.glance025DurationProbe.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_glance_025_duration_failure \
      benchmarkStep.glance025DurationProbe.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local duration_args=(
    --attempts 1
    --network-condition constrained-cellular
    --visual-transport vnc
    --stream-shape-frame-interval 0
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-poor-network-traffic-v1
    --stream-shape-transport request-response
    --stream-shape-request-pipeline-depth 1
    --stream-shape-request-region viewport-phone-portrait
    --stream-shape-first-frame-request visible-glance
    --stream-shape-first-frame-visible-glance-scale 0.25
    --stream-shape-profiles local-low-latency-rgb565
    --stream-shape-profile-order fixed
    --stream-shape-profile-iterations 1
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 0
    --stream-shape-duration-seconds 12
    --timeout 30
    --idle-timeout 5
    --safe-progress-label-file "$progress_file"
    --json
  )

  write_bounded_sweep_phase "$phase_file" benchmark-running
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-duration-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout 90 "$BOUNDED_BENCHMARK_EXECUTABLE" "${duration_args[@]}" >"$output_file" 2>/dev/null && [[ -s "$output_file" ]]; then
    printf '{"schemaVersion":1,"mode":"glance-025-duration-probe","profileLabel":"local-low-latency-rgb565","scalePermille":250,"status":"passed","report":'
    cat "$output_file"
    printf '}\n'
    rm -f "$phase_file" "$progress_file" "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_glance_025_duration_failure \
      benchmarkStep.glance025DurationProbe.timedOut \
      "$phase_file" \
      "$progress_file"
  else
    json_glance_025_duration_failure \
      benchmarkStep.glance025DurationProbe.failed \
      "$phase_file" \
      "$progress_file"
  fi
  rm -f "$phase_file" "$progress_file" "$output_file"
}

json_glance_025_10fps_duration_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"glance-025-10fps-duration-probe","profileLabel":"local-low-latency-rgb565","scalePermille":250,"targetLabel":"iphone-remote-desktop-10fps-v1","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

run_glance_025_10fps_duration_probe() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-10fps-duration-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-10fps-duration-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_glance_025_10fps_duration_failure \
        benchmarkStep.glance02510fpsDurationProbe.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_glance_025_10fps_duration_failure \
        benchmarkStep.glance02510fpsDurationProbe.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_glance_025_10fps_duration_failure \
      benchmarkStep.glance02510fpsDurationProbe.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local duration_args=(
    --attempts 1
    --network-condition constrained-cellular
    --visual-transport vnc
    --stream-shape-frame-interval 0
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-remote-desktop-10fps-v1
    --stream-shape-transport request-response
    --stream-shape-request-pipeline-depth 1
    --stream-shape-request-region viewport-phone-portrait
    --stream-shape-first-frame-request visible-glance
    --stream-shape-first-frame-visible-glance-scale 0.25
    --stream-shape-profiles local-low-latency-rgb565
    --stream-shape-profile-order fixed
    --stream-shape-profile-iterations 1
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 0
    --stream-shape-duration-seconds 12
    --timeout 30
    --idle-timeout 5
    --safe-progress-label-file "$progress_file"
    --json
  )

  write_bounded_sweep_phase "$phase_file" benchmark-running
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-10fps-duration-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout 90 "$BOUNDED_BENCHMARK_EXECUTABLE" "${duration_args[@]}" >"$output_file" 2>/dev/null && [[ -s "$output_file" ]]; then
    printf '{"schemaVersion":1,"mode":"glance-025-10fps-duration-probe","profileLabel":"local-low-latency-rgb565","scalePermille":250,"targetLabel":"iphone-remote-desktop-10fps-v1","status":"passed","report":'
    cat "$output_file"
    printf '}\n'
    rm -f "$phase_file" "$progress_file" "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_glance_025_10fps_duration_failure \
      benchmarkStep.glance02510fpsDurationProbe.timedOut \
      "$phase_file" \
      "$progress_file"
  else
    json_glance_025_10fps_duration_failure \
      benchmarkStep.glance02510fpsDurationProbe.failed \
      "$phase_file" \
      "$progress_file"
  fi
  rm -f "$phase_file" "$progress_file" "$output_file"
}

json_remote_desktop_10fps_profile_sweep_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-profile-cadence-sweep","targetLabel":"iphone-remote-desktop-10fps-v1","scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_remote_desktop_10fps_profile_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="$3"
  local profile_label
  profile_label="$(bounded_drilldown_profile_label "$4")"
  local profile_ordinal="$5"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-profile-cadence-profile","profileLabel":'
  json_string "$profile_label"
  printf ',"profileOrdinal":%d,"targetLabel":"iphone-remote-desktop-10fps-v1","scalePermille":250,"status":"failed","safeFailureCode":' "$profile_ordinal"
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}'
}

json_remote_desktop_10fps_profile_result() {
  local phase_file="$1"
  local progress_file="$2"
  local profile_label
  profile_label="$(bounded_drilldown_profile_label "$3")"
  local profile_ordinal="$4"
  shift 4

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-profile-output.XXXXXX")"
  : >"$progress_file"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout 90 "$@" >"$output_file" 2>/dev/null \
    && json_file_is_valid_or_unchecked "$output_file"; then
    printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-profile-cadence-profile","profileLabel":'
    json_string "$profile_label"
    printf ',"profileOrdinal":%d,"targetLabel":"iphone-remote-desktop-10fps-v1","scalePermille":250,"status":"passed","report":' "$profile_ordinal"
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_remote_desktop_10fps_profile_failure \
      benchmarkStep.remoteDesktop10fpsProfileCadenceSweep.timedOut \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal"
  else
    json_remote_desktop_10fps_profile_failure \
      benchmarkStep.remoteDesktop10fpsProfileCadenceSweep.failed \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal"
  fi
  rm -f "$output_file"
}

remote_desktop_10fps_profile_args() {
  local profile_label="$1"
  local progress_file="$2"
  REMOTE_DESKTOP_10FPS_PROFILE_ARGS=(
    --attempts 1
    --network-condition constrained-cellular
    --visual-transport vnc
    --stream-shape-frame-interval 0
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-remote-desktop-10fps-v1
    --stream-shape-transport request-response
    --stream-shape-request-pipeline-depth 1
    --stream-shape-request-region viewport-phone-portrait
    --stream-shape-first-frame-request visible-glance
    --stream-shape-first-frame-visible-glance-scale 0.25
    --stream-shape-profiles "$profile_label"
    --stream-shape-profile-order fixed
    --stream-shape-profile-iterations 1
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 0
    --stream-shape-duration-seconds 12
    --timeout 30
    --idle-timeout 5
    --safe-progress-label-file "$progress_file"
    --json
  )
}

run_remote_desktop_10fps_profile_cadence_sweep() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-profile-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-profile-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_remote_desktop_10fps_profile_sweep_failure \
        benchmarkStep.remoteDesktop10fpsProfileCadenceSweep.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_remote_desktop_10fps_profile_sweep_failure \
        benchmarkStep.remoteDesktop10fpsProfileCadenceSweep.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_remote_desktop_10fps_profile_sweep_failure \
      benchmarkStep.remoteDesktop10fpsProfileCadenceSweep.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local profiles=(
    local-low-latency-rgb565
    tight-first-cursor
    tight-first
  )
  local first_profile=1
  local profile_label
  local profile_ordinal=0
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-profile-cadence-sweep","status":"completed","targetLabel":"iphone-remote-desktop-10fps-v1","minimumContentFPS":10,"scalePermille":250,"diagnosticPolicyLabels":["same-target-profile-comparison","first-byte-wait-dominance-indicates-server-cadence","payload-client-renderer-low-cost-does-not-justify-profile-promotion"],"profiles":[\n'
  for profile_label in "${profiles[@]}"; do
    profile_ordinal=$((profile_ordinal + 1))
    if ((first_profile)); then
      first_profile=0
    else
      printf ',\n'
    fi
    write_bounded_sweep_phase "$phase_file" benchmark-running
    remote_desktop_10fps_profile_args "$profile_label" "$progress_file"
    json_remote_desktop_10fps_profile_result \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal" \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${REMOTE_DESKTOP_10FPS_PROFILE_ARGS[@]}"
  done
  printf '\n],"nextActionLabels":["inspect-server-transport-cadence-when-first-byte-wait-fails","do-not-promote-profile-without-10fps-pass","compare-true-helper-video-after-screen-recording-permission"]}\n'
  rm -f "$phase_file" "$progress_file"
}

json_remote_desktop_10fps_server_cadence_probe_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-server-cadence-probe","targetLabel":"iphone-remote-desktop-10fps-v1","profileLabel":"local-low-latency-rgb565","scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_remote_desktop_10fps_server_cadence_candidate_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="$3"
  local candidate_label="$4"
  local candidate_ordinal="$5"
  local network_condition="$6"
  local request_region="$7"
  local first_frame_request="$8"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-server-cadence-candidate","candidateLabel":'
  json_string "$candidate_label"
  printf ',"candidateOrdinal":%d,"targetLabel":"iphone-remote-desktop-10fps-v1","profileLabel":"local-low-latency-rgb565","networkCondition":' "$candidate_ordinal"
  json_string "$network_condition"
  printf ',"requestRegion":'
  json_string "$request_region"
  printf ',"firstFrameRequestMode":'
  json_string "$first_frame_request"
  printf ',"scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}'
}

json_remote_desktop_10fps_server_cadence_candidate_result() {
  local phase_file="$1"
  local progress_file="$2"
  local candidate_label="$3"
  local candidate_ordinal="$4"
  local network_condition="$5"
  local request_region="$6"
  local first_frame_request="$7"
  shift 7

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-server-cadence-output.XXXXXX")"
  : >"$progress_file"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout 90 "$@" >"$output_file" 2>/dev/null \
    && json_file_is_valid_or_unchecked "$output_file"; then
    printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-server-cadence-candidate","candidateLabel":'
    json_string "$candidate_label"
    printf ',"candidateOrdinal":%d,"targetLabel":"iphone-remote-desktop-10fps-v1","profileLabel":"local-low-latency-rgb565","networkCondition":' "$candidate_ordinal"
    json_string "$network_condition"
    printf ',"requestRegion":'
    json_string "$request_region"
    printf ',"firstFrameRequestMode":'
    json_string "$first_frame_request"
    printf ',"scalePermille":250,"status":"passed","report":'
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_remote_desktop_10fps_server_cadence_candidate_failure \
      benchmarkStep.remoteDesktop10fpsServerCadenceProbe.timedOut \
      "$phase_file" \
      "$progress_file" \
      "$candidate_label" \
      "$candidate_ordinal" \
      "$network_condition" \
      "$request_region" \
      "$first_frame_request"
  else
    json_remote_desktop_10fps_server_cadence_candidate_failure \
      benchmarkStep.remoteDesktop10fpsServerCadenceProbe.failed \
      "$phase_file" \
      "$progress_file" \
      "$candidate_label" \
      "$candidate_ordinal" \
      "$network_condition" \
      "$request_region" \
      "$first_frame_request"
  fi
  rm -f "$output_file"
}

remote_desktop_10fps_server_cadence_args() {
  local network_condition="$1"
  local request_region="$2"
  local first_frame_request="$3"
  local progress_file="$4"
  REMOTE_DESKTOP_10FPS_SERVER_CADENCE_ARGS=(
    --attempts 1
    --network-condition "$network_condition"
    --visual-transport vnc
    --stream-shape-frame-interval 0
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-remote-desktop-10fps-v1
    --stream-shape-transport request-response
    --stream-shape-request-pipeline-depth 1
    --stream-shape-request-region "$request_region"
    --stream-shape-first-frame-request "$first_frame_request"
    --stream-shape-first-frame-visible-glance-scale 0.25
    --stream-shape-profiles local-low-latency-rgb565
    --stream-shape-profile-order fixed
    --stream-shape-profile-iterations 1
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 0
    --stream-shape-duration-seconds 12
    --timeout 30
    --idle-timeout 5
    --safe-progress-label-file "$progress_file"
    --json
  )
}

run_remote_desktop_10fps_server_cadence_probe() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-server-cadence-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-server-cadence-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_remote_desktop_10fps_server_cadence_probe_failure \
        benchmarkStep.remoteDesktop10fpsServerCadenceProbe.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_remote_desktop_10fps_server_cadence_probe_failure \
        benchmarkStep.remoteDesktop10fpsServerCadenceProbe.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_remote_desktop_10fps_server_cadence_probe_failure \
      benchmarkStep.remoteDesktop10fpsServerCadenceProbe.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local candidates=(
    "constrained-viewport-visible|constrained-cellular|viewport-phone-portrait|visible-glance"
    "local-viewport-visible|none|viewport-phone-portrait|visible-glance"
    "constrained-viewport-full-startup|constrained-cellular|viewport-phone-portrait|full"
    "constrained-full-full-startup|constrained-cellular|full|full"
  )
  local first_candidate=1
  local candidate
  local candidate_ordinal=0
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-server-cadence-probe","status":"completed","targetLabel":"iphone-remote-desktop-10fps-v1","minimumContentFPS":10,"profileLabel":"local-low-latency-rgb565","scalePermille":250,"diagnosticPolicyLabels":["same-profile-server-cadence-comparison","network-conditioning-axis-isolates-tailnet-vs-poor-link-first-byte-wait","request-region-axis-checks-viewport-aware-server-delay","first-frame-axis-checks-startup-region-side-effect"],"candidates":[\n'
  for candidate in "${candidates[@]}"; do
    candidate_ordinal=$((candidate_ordinal + 1))
    IFS='|' read -r candidate_label network_condition request_region first_frame_request <<<"$candidate"
    if ((first_candidate)); then
      first_candidate=0
    else
      printf ',\n'
    fi
    write_bounded_sweep_phase "$phase_file" benchmark-running
    remote_desktop_10fps_server_cadence_args \
      "$network_condition" \
      "$request_region" \
      "$first_frame_request" \
      "$progress_file"
    json_remote_desktop_10fps_server_cadence_candidate_result \
      "$phase_file" \
      "$progress_file" \
      "$candidate_label" \
      "$candidate_ordinal" \
      "$network_condition" \
      "$request_region" \
      "$first_frame_request" \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${REMOTE_DESKTOP_10FPS_SERVER_CADENCE_ARGS[@]}"
  done
  printf '\n],"nextActionLabels":["inspect-server-update-cadence-if-first-byte-wait-persists-with-network-condition-none","keep-helper-video-as-primary-smoothness-path-until-vnc-reaches-10fps","do-not-promote-request-region-or-startup-mode-without-10fps-pass"]}\n'
  rm -f "$phase_file" "$progress_file"
}

json_remote_desktop_10fps_transport_cadence_drilldown_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-transport-cadence-drilldown","targetLabel":"iphone-remote-desktop-10fps-v1","profileLabel":"local-low-latency-rgb565","scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_remote_desktop_10fps_transport_cadence_candidate_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="$3"
  local candidate_label="$4"
  local candidate_ordinal="$5"
  local transport_mode="$6"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-transport-cadence-candidate","candidateLabel":'
  json_string "$candidate_label"
  printf ',"candidateOrdinal":%d,"targetLabel":"iphone-remote-desktop-10fps-v1","profileLabel":"local-low-latency-rgb565","transportMode":' "$candidate_ordinal"
  json_string "$transport_mode"
  printf ',"networkCondition":"none","requestRegion":"viewport-phone-portrait","firstFrameRequestMode":"visible-glance","scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}'
}

json_remote_desktop_10fps_transport_cadence_candidate_result() {
  local phase_file="$1"
  local progress_file="$2"
  local candidate_label="$3"
  local candidate_ordinal="$4"
  local transport_mode="$5"
  shift 5

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-transport-cadence-output.XXXXXX")"
  : >"$progress_file"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout 90 "$@" >"$output_file" 2>/dev/null \
    && json_file_is_valid_or_unchecked "$output_file"; then
    printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-transport-cadence-candidate","candidateLabel":'
    json_string "$candidate_label"
    printf ',"candidateOrdinal":%d,"targetLabel":"iphone-remote-desktop-10fps-v1","profileLabel":"local-low-latency-rgb565","transportMode":' "$candidate_ordinal"
    json_string "$transport_mode"
    printf ',"networkCondition":"none","requestRegion":"viewport-phone-portrait","firstFrameRequestMode":"visible-glance","scalePermille":250,"status":"passed","report":'
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_remote_desktop_10fps_transport_cadence_candidate_failure \
      benchmarkStep.remoteDesktop10fpsTransportCadenceDrilldown.timedOut \
      "$phase_file" \
      "$progress_file" \
      "$candidate_label" \
      "$candidate_ordinal" \
      "$transport_mode"
  else
    json_remote_desktop_10fps_transport_cadence_candidate_failure \
      benchmarkStep.remoteDesktop10fpsTransportCadenceDrilldown.failed \
      "$phase_file" \
      "$progress_file" \
      "$candidate_label" \
      "$candidate_ordinal" \
      "$transport_mode"
  fi
  rm -f "$output_file"
}

remote_desktop_10fps_transport_cadence_args() {
  local transport_mode="$1"
  local progress_file="$2"
  REMOTE_DESKTOP_10FPS_TRANSPORT_CADENCE_ARGS=(
    --attempts 1
    --network-condition none
    --visual-transport vnc
    --stream-shape-frame-interval 0
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-remote-desktop-10fps-v1
    --stream-shape-transport "$transport_mode"
    --stream-shape-request-pipeline-depth 1
    --stream-shape-request-region viewport-phone-portrait
    --stream-shape-first-frame-request visible-glance
    --stream-shape-first-frame-visible-glance-scale 0.25
    --stream-shape-profiles local-low-latency-rgb565
    --stream-shape-profile-order fixed
    --stream-shape-profile-iterations 1
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 0
    --stream-shape-duration-seconds 12
    --timeout 30
    --idle-timeout 5
    --safe-progress-label-file "$progress_file"
    --json
  )
}

run_remote_desktop_10fps_transport_cadence_drilldown() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-transport-cadence-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-remote-desktop-10fps-transport-cadence-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_remote_desktop_10fps_transport_cadence_drilldown_failure \
        benchmarkStep.remoteDesktop10fpsTransportCadenceDrilldown.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_remote_desktop_10fps_transport_cadence_drilldown_failure \
        benchmarkStep.remoteDesktop10fpsTransportCadenceDrilldown.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_remote_desktop_10fps_transport_cadence_drilldown_failure \
      benchmarkStep.remoteDesktop10fpsTransportCadenceDrilldown.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local candidates=(
    "request-response-baseline|request-response"
    "continuous-updates-attempt|continuous-updates"
  )
  local first_candidate=1
  local candidate
  local candidate_ordinal=0
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-transport-cadence-drilldown","status":"completed","targetLabel":"iphone-remote-desktop-10fps-v1","minimumContentFPS":10,"profileLabel":"local-low-latency-rgb565","networkCondition":"none","requestRegion":"viewport-phone-portrait","firstFrameRequestMode":"visible-glance","scalePermille":250,"diagnosticPolicyLabels":["transport-mode-comparison","request-response-demand-driven-first-byte-wait","continuous-updates-extension-check","do-not-promote-transport-without-10fps-pass"],"candidates":[\n'
  for candidate in "${candidates[@]}"; do
    candidate_ordinal=$((candidate_ordinal + 1))
    IFS='|' read -r candidate_label transport_mode <<<"$candidate"
    if ((first_candidate)); then
      first_candidate=0
    else
      printf ',\n'
    fi
    write_bounded_sweep_phase "$phase_file" benchmark-running
    remote_desktop_10fps_transport_cadence_args "$transport_mode" "$progress_file"
    json_remote_desktop_10fps_transport_cadence_candidate_result \
      "$phase_file" \
      "$progress_file" \
      "$candidate_label" \
      "$candidate_ordinal" \
      "$transport_mode" \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${REMOTE_DESKTOP_10FPS_TRANSPORT_CADENCE_ARGS[@]}"
  done
  printf '\n],"nextActionLabels":["if-continuous-updates-fails-keep-vnc-request-response-as-fallback","if-request-response-first-byte-wait-persists-prioritize-helper-video","rerun-after-server-cadence-or-helper-permission-changes"]}\n'
  rm -f "$phase_file" "$progress_file"
}

json_glance_025_profile_sweep_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="${3:-}"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"glance-025-profile-sweep","scalePermille":250,"status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}\n'
}

json_glance_025_profile_failure() {
  local failure_code="$1"
  local phase_file="$2"
  local progress_file="$3"
  local profile_label
  profile_label="$(bounded_drilldown_profile_label "$4")"
  local profile_ordinal="$5"
  local phase_label
  phase_label="$(bounded_sweep_phase_label "$phase_file")"
  printf '{"schemaVersion":1,"mode":"glance-025-profile-sweep-profile","profileLabel":'
  json_string "$profile_label"
  printf ',"profileOrdinal":%d,"scalePermille":250,"status":"failed","safeFailureCode":' "$profile_ordinal"
  json_string "$failure_code"
  printf ',"lastPhaseLabel":'
  json_string "$phase_label"
  print_benchmark_progress_fields "$progress_file"
  printf '}'
}

json_glance_025_profile_result() {
  local phase_file="$1"
  local progress_file="$2"
  local profile_label
  profile_label="$(bounded_drilldown_profile_label "$3")"
  local profile_ordinal="$4"
  shift 4

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-profile-output.XXXXXX")"
  : >"$progress_file"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout 90 "$@" >"$output_file" 2>/dev/null && [[ -s "$output_file" ]]; then
    printf '{"schemaVersion":1,"mode":"glance-025-profile-sweep-profile","profileLabel":'
    json_string "$profile_label"
    printf ',"profileOrdinal":%d,"scalePermille":250,"status":"passed","report":' "$profile_ordinal"
    cat "$output_file"
    printf '}'
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    json_glance_025_profile_failure \
      benchmarkStep.glance025ProfileSweep.timedOut \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal"
  else
    json_glance_025_profile_failure \
      benchmarkStep.glance025ProfileSweep.failed \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal"
  fi
  rm -f "$output_file"
}

glance_025_profile_args() {
  local profile_label="$1"
  local progress_file="$2"
  GLANCE_025_PROFILE_ARGS=(
    --attempts 1
    --network-condition constrained-cellular
    --visual-transport vnc
    --stream-shape-frame-interval 0
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-poor-network-traffic-v1
    --stream-shape-transport request-response
    --stream-shape-request-pipeline-depth 1
    --stream-shape-request-region viewport-phone-portrait
    --stream-shape-first-frame-request visible-glance
    --stream-shape-first-frame-visible-glance-scale 0.25
    --stream-shape-profiles "$profile_label"
    --stream-shape-profile-order fixed
    --stream-shape-profile-iterations 1
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 0
    --stream-shape-duration-seconds 12
    --timeout 30
    --idle-timeout 5
    --safe-progress-label-file "$progress_file"
    --json
  )
}

run_glance_025_profile_sweep() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-profile-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-025-profile-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_glance_025_profile_sweep_failure \
        benchmarkStep.glance025ProfileSweep.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_glance_025_profile_sweep_failure \
        benchmarkStep.glance025ProfileSweep.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_glance_025_profile_sweep_failure \
      benchmarkStep.glance025ProfileSweep.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local profiles=(
    tight-first-cursor
    local-low-latency-rgb565
    zrle-compression-0
    zrle-compression-0-rgb565
    adaptive-good-full
  )
  local first_profile=1
  local profile_label
  local profile_ordinal=0
  printf '{"schemaVersion":1,"mode":"glance-025-profile-sweep","status":"completed","scalePermille":250,"profiles":[\n'
  for profile_label in "${profiles[@]}"; do
    profile_ordinal=$((profile_ordinal + 1))
    if ((first_profile)); then
      first_profile=0
    else
      printf ',\n'
    fi
    write_bounded_sweep_phase "$phase_file" benchmark-running
    glance_025_profile_args "$profile_label" "$progress_file"
    json_glance_025_profile_result \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal" \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${GLANCE_025_PROFILE_ARGS[@]}"
  done
  printf '\n]}\n'
  rm -f "$phase_file" "$progress_file"
}

bounded_benchmark_executable() {
  local build_bin_path
  build_bin_path="$(cd "$repo_root" && swift build --show-bin-path 2>/dev/null || true)"

  local candidates=()
  if [[ -n "$build_bin_path" ]]; then
    candidates+=("$build_bin_path/VNCLiveBenchmark")
  fi
  candidates+=("$repo_root/.build/debug/VNCLiveBenchmark")

  local candidate
  for candidate in "$repo_root"/.build/*/debug/VNCLiveBenchmark; do
    [[ -e "$candidate" ]] && candidates+=("$candidate")
  done

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
}

prepare_bounded_benchmark_executable() {
  local phase_file="$1"
  BOUNDED_BENCHMARK_EXECUTABLE=""
  write_bounded_sweep_phase "$phase_file" swift-build
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if ! run_with_wall_timeout 30 swift build --product VNCLiveBenchmark >/dev/null 2>/dev/null; then
    return 1
  fi

  local benchmark_executable
  benchmark_executable="$(bounded_benchmark_executable)"
  if [[ -z "$benchmark_executable" ]]; then
    return 1
  fi
  BOUNDED_BENCHMARK_EXECUTABLE="$benchmark_executable"
}

run_bounded_vnc_profile_sweep() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-bounded-sweep-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-bounded-sweep-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  local bounded_args=("$@")
  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_bounded_sweep_failure benchmarkStep.boundedVNCProfileSweep.timedOut "$phase_file" "$progress_file"
    else
      json_bounded_sweep_failure benchmarkStep.boundedVNCProfileSweep.failed "$phase_file" "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_bounded_sweep_failure benchmarkStep.boundedVNCProfileSweep.failed "$phase_file" "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  bounded_args+=(--safe-progress-label-file "$progress_file")
  write_bounded_sweep_phase "$phase_file" benchmark-running
  json_benchmark_or_timeout_failure \
    45 \
    "$phase_file" \
    "$progress_file" \
    "$BOUNDED_BENCHMARK_EXECUTABLE" "${bounded_args[@]}"
  rm -f "$phase_file" "$progress_file"
}

run_bounded_vnc_profile_drilldown() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-bounded-drilldown-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-bounded-drilldown-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_bounded_drilldown_runner_failure benchmarkStep.boundedVNCProfileDrilldown.timedOut "$phase_file"
    else
      json_bounded_drilldown_runner_failure benchmarkStep.boundedVNCProfileDrilldown.failed "$phase_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_bounded_drilldown_runner_failure benchmarkStep.boundedVNCProfileDrilldown.failed "$phase_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local profiles=(tight-first zrle-compression-0 adaptive-good-full)
  local first_profile=1
  local profile_label
  local profile_ordinal=0
  printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-drilldown","status":"completed","profiles":[\n'
  for profile_label in "${profiles[@]}"; do
    profile_ordinal=$((profile_ordinal + 1))
    if ((first_profile)); then
      first_profile=0
    else
      printf ',\n'
    fi
    write_bounded_sweep_phase "$phase_file" benchmark-running
    local profile_args=(
      --attempts 1
      --stream-shape-frame-interval 0.0166666667
      --stream-shape-idle-frame-interval 0.05
      --stream-shape-empty-backoff app
      --stream-shape-power-mode normal
      --stream-shape-client-pressure app
      --stream-shape-viewport-interaction off
      --stream-shape-stimulus external-command
      --stream-shape-stimulus-warmup-seconds 0.25
      --stream-shape-stimulus-frame-interval 0.0833333333
      --stream-shape-preflight-frames 0
      --stream-shape-practical-target iphone-sustained-usability-v2
      --stream-shape-transport request-response
      --stream-shape-profiles "$profile_label"
      --stream-shape-profile-order fixed
      --stream-shape-profile-iterations 1
      --first-frame-profiles none
      --full-refresh-samples 0
      --continuous-update-samples 0
      --stream-shape-samples 1
      --stream-shape-duration-seconds 1
      --timeout 5
      --idle-timeout 1
      --safe-progress-label-file "$progress_file"
      --json
    )
    if ((extra_arg_count)); then
      profile_args+=("${extra_args[@]}")
    fi
    json_bounded_drilldown_profile_result \
      "$phase_file" \
      "$progress_file" \
      "$profile_label" \
      "$profile_ordinal" \
      20 \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${profile_args[@]}"
  done
  printf '\n]}\n'
  rm -f "$phase_file" "$progress_file"
}

run_bounded_vnc_candidate_stability() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-candidate-stability-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-candidate-stability-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_bounded_candidate_stability_failure \
        benchmarkStep.boundedVNCCandidateStability.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_bounded_candidate_stability_failure \
        benchmarkStep.boundedVNCCandidateStability.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_bounded_candidate_stability_failure \
      benchmarkStep.boundedVNCCandidateStability.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local stability_args=(
    --attempts 1
    --stream-shape-frame-interval 0.0166666667
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-sustained-usability-v2
    --stream-shape-transport request-response
    --stream-shape-profiles tight-first,tight-first-rgb565,adaptive-good-full
    --stream-shape-profile-order rotate
    --stream-shape-profile-iterations 3
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 2
    --stream-shape-duration-seconds 2
    --timeout 8
    --idle-timeout 2
    --safe-progress-label-file "$progress_file"
    --json
  )
  if ((extra_arg_count)); then
    stability_args+=("${extra_args[@]}")
  fi

  write_bounded_sweep_phase "$phase_file" benchmark-running
  # Three profiles across three iterations need a little more wall-clock room.
  json_benchmark_or_candidate_stability_failure \
    120 \
    "$phase_file" \
    "$progress_file" \
    "$BOUNDED_BENCHMARK_EXECUTABLE" "${stability_args[@]}"
  rm -f "$phase_file" "$progress_file"
}

run_bounded_vnc_tight_cursor_stability() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-tight-cursor-stability-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-tight-cursor-stability-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_bounded_tight_cursor_stability_failure \
        benchmarkStep.boundedVNCTightCursorStability.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_bounded_tight_cursor_stability_failure \
        benchmarkStep.boundedVNCTightCursorStability.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_bounded_tight_cursor_stability_failure \
      benchmarkStep.boundedVNCTightCursorStability.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local stability_args=(
    --attempts 1
    --stream-shape-frame-interval 0.0166666667
    --stream-shape-idle-frame-interval 0.05
    --stream-shape-empty-backoff app
    --stream-shape-power-mode normal
    --stream-shape-client-pressure app
    --stream-shape-viewport-interaction off
    --stream-shape-stimulus external-command
    --stream-shape-stimulus-warmup-seconds 0.25
    --stream-shape-stimulus-frame-interval 0.0833333333
    --stream-shape-preflight-frames 0
    --stream-shape-practical-target iphone-sustained-usability-v2
    --stream-shape-transport request-response
    --stream-shape-profiles tight-first,tight-first-cursor
    --stream-shape-profile-order rotate
    --stream-shape-profile-iterations 3
    --first-frame-profiles none
    --full-refresh-samples 0
    --continuous-update-samples 0
    --stream-shape-samples 2
    --stream-shape-duration-seconds 2
    --timeout 8
    --idle-timeout 2
    --safe-progress-label-file "$progress_file"
    --json
  )
  if ((extra_arg_count)); then
    stability_args+=("${extra_args[@]}")
  fi

  write_bounded_sweep_phase "$phase_file" benchmark-running
  json_benchmark_or_tight_cursor_stability_failure \
    90 \
    "$phase_file" \
    "$progress_file" \
    "$BOUNDED_BENCHMARK_EXECUTABLE" "${stability_args[@]}"
  rm -f "$phase_file" "$progress_file"
}

run_bounded_vnc_tight_cursor_depth_sweep() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-tight-cursor-depth-phase.XXXXXX")"
  local progress_file
  progress_file="$(mktemp "${TMPDIR:-/tmp}/naru-tight-cursor-depth-progress.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_bounded_tight_cursor_depth_sweep_failure \
        benchmarkStep.boundedVNCTightCursorDepthSweep.timedOut \
        "$phase_file" \
        "$progress_file"
    else
      json_bounded_tight_cursor_depth_sweep_failure \
        benchmarkStep.boundedVNCTightCursorDepthSweep.failed \
        "$phase_file" \
        "$progress_file"
    fi
    rm -f "$phase_file" "$progress_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    json_bounded_tight_cursor_depth_sweep_failure \
      benchmarkStep.boundedVNCTightCursorDepthSweep.failed \
      "$phase_file" \
      "$progress_file"
    rm -f "$phase_file" "$progress_file"
    return
  fi

  local first_depth=1
  local depth
  printf '{"schemaVersion":1,"mode":"bounded-vnc-tight-cursor-depth-sweep","status":"completed","profileLabel":"tight-first-cursor","depths":[\n'
  for depth in 1 2 3; do
    if ((first_depth)); then
      first_depth=0
    else
      printf ',\n'
    fi
    write_bounded_sweep_phase "$phase_file" benchmark-running
    local depth_args=(
      --attempts 1
      --stream-shape-frame-interval 0.0166666667
      --stream-shape-idle-frame-interval 0.05
      --stream-shape-empty-backoff app
      --stream-shape-power-mode normal
      --stream-shape-client-pressure app
      --stream-shape-viewport-interaction off
      --stream-shape-stimulus external-command
      --stream-shape-stimulus-warmup-seconds 0.25
      --stream-shape-stimulus-frame-interval 0.0833333333
      --stream-shape-preflight-frames 0
      --stream-shape-practical-target iphone-sustained-usability-v2
      --stream-shape-transport request-response
      --stream-shape-request-pipeline-depth "$depth"
      --stream-shape-profiles tight-first-cursor
      --stream-shape-profile-order fixed
      --stream-shape-profile-iterations 1
      --first-frame-profiles none
      --full-refresh-samples 0
      --continuous-update-samples 0
      --stream-shape-samples 12
      --stream-shape-duration-seconds 10
      --timeout 16
      --idle-timeout 2
      --safe-progress-label-file "$progress_file"
      --json
    )
    if ((extra_arg_count)); then
      depth_args+=("${extra_args[@]}")
    fi
    json_bounded_tight_cursor_depth_result \
      "$phase_file" \
      "$progress_file" \
      "$depth" \
      30 \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${depth_args[@]}"
  done
  printf '\n]}\n'
  rm -f "$phase_file" "$progress_file"
}

run_glance_scale_sweep() {
  local phase_file
  phase_file="$(mktemp "${TMPDIR:-/tmp}/naru-glance-scale-phase.XXXXXX")"
  write_bounded_sweep_phase "$phase_file" runner-starting

  if ! prepare_bounded_benchmark_executable "$phase_file"; then
    printf '{"schemaVersion":1,"mode":"glance-scale-sweep","status":"failed","safeFailureCode":'
    if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
      json_string benchmarkStep.glanceScaleSweep.timedOut
    else
      json_string benchmarkStep.glanceScaleSweep.failed
    fi
    printf ',"lastPhaseLabel":'
    json_string "$(bounded_sweep_phase_label "$phase_file")"
    printf '}\n'
    rm -f "$phase_file"
    return
  fi

  if [[ -z "$BOUNDED_BENCHMARK_EXECUTABLE" ]]; then
    printf '{"schemaVersion":1,"mode":"glance-scale-sweep","status":"failed","safeFailureCode":"benchmarkStep.glanceScaleSweep.failed","lastPhaseLabel":'
    json_string "$(bounded_sweep_phase_label "$phase_file")"
    printf '}\n'
    rm -f "$phase_file"
    return
  fi

  local first_scale=1
  local scale
  printf '{"schemaVersion":1,"mode":"glance-scale-sweep","status":"completed","scales":[\n'
  for scale in 0.45 0.35 0.25; do
    if ((first_scale)); then
      first_scale=0
    else
      printf ',\n'
    fi
    local scale_permille
    case "$scale" in
      0.45) scale_permille=450 ;;
      0.35) scale_permille=350 ;;
      0.25) scale_permille=250 ;;
      *) scale_permille=0 ;;
    esac
    write_bounded_sweep_phase "$phase_file" benchmark-running
    local scale_args=(
      --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic
      --visual-transport vnc,helper-video
      --helper-video-probe external-helper-synthetic-encoded-tcp
      --first-frame-profiles none
      --full-refresh-samples 0
      --continuous-update-samples 0
      --stream-shape-samples 2
      --stream-shape-duration-seconds 3
      --stream-shape-first-frame-visible-glance-scale "$scale"
      --json
    )
    json_glance_scale_sweep_result \
      "$phase_file" \
      "$scale" \
      "$scale_permille" \
      90 \
      "$BOUNDED_BENCHMARK_EXECUTABLE" "${scale_args[@]}"
  done
  printf '\n]}\n'
  rm -f "$phase_file"
}

reject_extra_args() {
  if ((extra_arg_count)); then
    printf 'Mode %s does not accept extra arguments after --.\n' "$mode" >&2
    exit 2
  fi
}

reject_extra_flag() {
  if ((extra_arg_count == 0)); then
    return
  fi

  local forbidden="$1"
  local arg
  for arg in "${extra_args[@]}"; do
    if [[ "$arg" == "$forbidden" || "$arg" == "$forbidden="* ]]; then
      printf 'Mode %s manages %s internally.\n' "$mode" "$forbidden" >&2
      exit 2
    fi
  done
}

reject_bounded_vnc_profile_flags() {
  reject_extra_flag --network-condition
  reject_extra_flag --environment-preflight
  reject_extra_flag --helper-video-probe-only
  reject_extra_flag --visual-transport
  reject_extra_flag --helper-video-probe
  reject_extra_flag --attempts
  reject_extra_flag --stream-shape-gate-preset
  reject_extra_flag --stream-shape-profiles
  reject_extra_flag --stream-shape-transport
  reject_extra_flag --stream-shape-profile-order
  reject_extra_flag --stream-shape-profile-iterations
  reject_extra_flag --stream-shape-pacing-window
  reject_extra_flag --stream-shape-request-region
  reject_extra_flag --stream-shape-first-frame-request
  reject_extra_flag --stream-shape-first-frame-visible-glance-scale
  reject_extra_flag --stream-shape-request-pipeline-depth
  reject_extra_flag --first-frame-profiles
  reject_extra_flag --full-refresh-samples
  reject_extra_flag --continuous-update-samples
  reject_extra_flag --stream-shape-samples
  reject_extra_flag --stream-shape-duration-seconds
  reject_extra_flag --stream-shape-frame-interval
  reject_extra_flag --stream-shape-idle-frame-interval
  reject_extra_flag --stream-shape-empty-backoff
  reject_extra_flag --stream-shape-power-mode
  reject_extra_flag --stream-shape-client-pressure
  reject_extra_flag --stream-shape-viewport-interaction
  reject_extra_flag --stream-shape-viewport-interaction-pause-seconds
  reject_extra_flag --stream-shape-stimulus
  reject_extra_flag --stream-shape-stimulus-warmup-seconds
  reject_extra_flag --stream-shape-stimulus-frame-interval
  reject_extra_flag --stream-shape-preflight-frames
  reject_extra_flag --stream-shape-practical-target
  reject_extra_flag --timeout
  reject_extra_flag --idle-timeout
  reject_extra_flag --safe-progress-label-file
  reject_extra_flag --ask-password
  reject_extra_flag --help
  reject_extra_flag -h
  reject_extra_flag --json
}

json_step_or_fixed_failure() {
  local step="$1"
  local failure_code="$2"
  shift 2

  local output
  if output="$("$@" 2>/dev/null)" && [[ -n "$output" ]]; then
    printf '%s' "$output"
  else
    printf '{"status":"failed","step":"%s","safeFailureCode":"%s"}' \
      "$step" "$failure_code"
  fi
}

json_string_array() {
  local first=1
  local item
  local escaped
  printf '['
  for item in "$@"; do
    if ((first)); then
      first=0
    else
      printf ', '
    fi
    escaped="${item//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\n'/\\n}"
    escaped="${escaped//$'\r'/\\r}"
    escaped="${escaped//$'\t'/\\t}"
    printf '"%s"' "$escaped"
  done
  printf ']'
}

append_unique() {
  local array_name="$1"
  local value="$2"
  local existing
  eval "local current_values=(\"\${${array_name}[@]-}\")"
  for existing in "${current_values[@]}"; do
    [[ -n "$existing" && "$existing" == "$value" ]] && return 0
  done
  eval "$array_name+=(\"\$value\")"
}

physical_iphone_ids_from_devicectl() {
  if ! command -v xcrun >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local output_file
  local status=1
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-physical-devices.XXXXXX")"
  if xcrun devicectl list devices \
    --filter "hardwareProperties.deviceType == 'iPhone'" \
    --json-output "$output_file" >/dev/null 2>&1; then
    jq -r '
      .result.devices[]?
      | select((.connectionProperties.tunnelState // "available") != "unavailable")
      | select((.deviceProperties.ddiServicesAvailable // true) != false)
      | .hardwareProperties.udid // .identifier // empty
    ' "$output_file"
    status=$?
  fi
  rm -f "$output_file"
  return "$status"
}

physical_unavailable_iphone_count_from_devicectl() {
  if ! command -v xcrun >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf '0'
    return
  fi

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-physical-devices.XXXXXX")"
  if xcrun devicectl list devices \
    --filter "hardwareProperties.deviceType == 'iPhone'" \
    --json-output "$output_file" >/dev/null 2>&1; then
    jq -r '
      [
        .result.devices[]?
        | select(
          (.connectionProperties.tunnelState // "available") == "unavailable"
          or (.deviceProperties.ddiServicesAvailable // true) == false
        )
      ]
      | length
    ' "$output_file"
  else
    printf '0'
  fi
  rm -f "$output_file"
}

physical_unavailable_iphone_id_is_known() {
  local device_id="$1"
  if [[ -z "$device_id" ]] || ! command -v xcrun >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local output_file
  local match_count="0"
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-physical-devices.XXXXXX")"
  if xcrun devicectl list devices \
    --filter "hardwareProperties.deviceType == 'iPhone'" \
    --json-output "$output_file" >/dev/null 2>&1; then
    match_count="$(
      jq -r --arg device_id "$device_id" '
        [
          .result.devices[]?
          | select(
            ((.hardwareProperties.udid // .identifier // "") == $device_id)
            and (
              (.connectionProperties.tunnelState // "available") == "unavailable"
              or (.deviceProperties.ddiServicesAvailable // true) == false
            )
          )
        ]
        | length
      ' "$output_file"
    )"
  fi
  rm -f "$output_file"
  [[ "$match_count" != "0" ]]
}

physical_iphone_ids_from_xctrace() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  xcrun xctrace list devices 2>/dev/null |
    awk '
      /^== Devices ==/{in_devices=1; next}
      /^== Devices Offline ==/{in_devices=0}
      /^== Simulators ==/{in_devices=0}
      in_devices
    ' |
    grep -i 'iPhone' |
    sed -n 's/.*(\([0-9][0-9.]*\)) (\([0-9A-Fa-f-]\{24,\}\)).*/\2/p'
}

physical_iphone_ids() {
  if physical_iphone_ids_from_devicectl; then
    return 0
  fi
  physical_iphone_ids_from_xctrace
}

discover_physical_ios_device_id() {
  if [[ -n "${NARU_PHYSICAL_IOS_DEVICE_ID:-}" ]]; then
    printf '%s' "$NARU_PHYSICAL_IOS_DEVICE_ID"
    return
  fi

  local ids
  ids="$(physical_iphone_ids || true)"
  printf '%s\n' "$ids" | sed -n '/./{p;q;}'
}

physical_ios_device_id_is_iphone() {
  local device_id="$1"
  local detected_id
  local ids

  ids="$(physical_iphone_ids || true)"
  while IFS= read -r detected_id; do
    [[ "$detected_id" == "$device_id" ]] && return 0
  done <<< "$ids"
  return 1
}

physical_iphone_device_count() {
  local ids
  ids="$(physical_iphone_ids || true)"
  if [[ -z "$ids" ]]; then
    printf '0'
    return
  fi

  printf '%s\n' "$ids" |
    sed '/^$/d' |
    wc -l |
    tr -d ' '
}

apple_development_team_ids() {
  if ! command -v security >/dev/null 2>&1; then
    return 1
  fi

  security find-identity -v -p codesigning 2>/dev/null |
    awk '
      /Apple Development/ {
        if (match($0, /\([A-Z0-9]{10}\)/)) {
          print substr($0, RSTART + 1, RLENGTH - 2)
        }
      }
    ' |
    sort -u
}

resolve_physical_development_team() {
  if [[ -n "${NARU_XCODE_DEVELOPMENT_TEAM:-}" ]]; then
    PHYSICAL_DEVELOPMENT_TEAM_STATUS="environment"
    return
  fi

  local team_ids
  local team_count
  local first_team_id
  team_ids="$(apple_development_team_ids || true)"
  team_count="$(printf '%s\n' "$team_ids" | sed '/^$/d' | wc -l | tr -d ' ')"

  case "$team_count" in
    1)
      first_team_id="$(printf '%s\n' "$team_ids" | sed -n '/./{p;q;}')"
      if [[ -n "$first_team_id" ]]; then
        export NARU_XCODE_DEVELOPMENT_TEAM="$first_team_id"
        PHYSICAL_DEVELOPMENT_TEAM_STATUS="inferred"
        return
      fi
      ;;
    0)
      PHYSICAL_DEVELOPMENT_TEAM_STATUS="missing"
      return
      ;;
    *)
      PHYSICAL_DEVELOPMENT_TEAM_STATUS="ambiguous"
      return
      ;;
  esac

  PHYSICAL_DEVELOPMENT_TEAM_STATUS="missing"
}

physical_team_inference_self_test_failure() {
  local failure_code="$1"
  printf '{"schemaVersion":1,"mode":"physical-team-inference-self-test","status":"failed","safeFailureCode":'
  json_string "$failure_code"
  printf '}\n'
  exit 1
}

physical_team_inference_self_test_case() {
  local case_label="$1"
  local team_ids="$2"
  local expected_status="$3"
  local expected_env_presence="${4:-absent}"

  unset NARU_XCODE_DEVELOPMENT_TEAM
  NARU_TEAM_INFERENCE_SELF_TEST_IDS="$team_ids"
  PHYSICAL_DEVELOPMENT_TEAM_STATUS="missing"
  resolve_physical_development_team

  if [[ "$PHYSICAL_DEVELOPMENT_TEAM_STATUS" != "$expected_status" ]]; then
    physical_team_inference_self_test_failure "${case_label}.status"
  fi

  case "$expected_env_presence" in
    present)
      if [[ -z "${NARU_XCODE_DEVELOPMENT_TEAM:-}" ]]; then
        physical_team_inference_self_test_failure "${case_label}.teamMissing"
      fi
      ;;
    absent)
      if [[ -n "${NARU_XCODE_DEVELOPMENT_TEAM:-}" ]]; then
        physical_team_inference_self_test_failure "${case_label}.teamUnexpected"
      fi
      ;;
    *)
      physical_team_inference_self_test_failure "${case_label}.invalidExpectation"
      ;;
  esac
}

physical_team_inference_self_test() {
  reject_extra_args

  local ambiguous_team_ids
  ambiguous_team_ids=$'ABCD123456\nWXYZ123456'

  apple_development_team_ids() {
    printf '%s\n' "${NARU_TEAM_INFERENCE_SELF_TEST_IDS:-}"
  }

  physical_team_inference_self_test_case "missing" "" "missing" "absent"
  physical_team_inference_self_test_case "ambiguous" "$ambiguous_team_ids" "ambiguous" "absent"
  physical_team_inference_self_test_case "single" "ABCD123456" "inferred" "present"

  export NARU_XCODE_DEVELOPMENT_TEAM="EXPLICIT01"
  NARU_TEAM_INFERENCE_SELF_TEST_IDS="$ambiguous_team_ids"
  PHYSICAL_DEVELOPMENT_TEAM_STATUS="missing"
  resolve_physical_development_team
  if [[ "$PHYSICAL_DEVELOPMENT_TEAM_STATUS" != "environment" ]]; then
    physical_team_inference_self_test_failure "environment.status"
  fi
  if [[ "${NARU_XCODE_DEVELOPMENT_TEAM:-}" != "EXPLICIT01" ]]; then
    physical_team_inference_self_test_failure "environment.teamChanged"
  fi

  printf '{"schemaVersion":1,"mode":"physical-team-inference-self-test","status":"passed"}\n'
}

physical_preflight_build_status() {
  local device_id="$1"
  local output_file="$2"
  local args=(
    xcodebuild
    -project NaruRemote.xcodeproj
    -scheme NaruRemote
    -destination "platform=iOS,id=$device_id"
    build
  )
  if [[ -n "${NARU_XCODE_DEVELOPMENT_TEAM:-}" ]]; then
    args+=(DEVELOPMENT_TEAM="$NARU_XCODE_DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
  fi

  if "${args[@]}" >"$output_file" 2>&1; then
    printf 'passed'
  else
    printf 'failed'
  fi
}

physical_preflight() {
  reject_extra_args
  import_physical_device_env
  cd "$repo_root"

  local issue_codes=()
  local setup_actions=()
  local device_count
  local device_id
  local device_status
  local device_selection_source
  local unavailable_device_count
  local signing_identity_status
  local development_team_status
  local build_check_status
  local provisioning_profile_status="unknown"
  local xcode_account_status="unknown"

  device_count="$(physical_iphone_device_count)"
  unavailable_device_count="$(physical_unavailable_iphone_count_from_devicectl)"
  device_id="$(discover_physical_ios_device_id)"
  if [[ -n "${NARU_PHYSICAL_IOS_DEVICE_ID:-}" ]]; then
    device_selection_source="environment"
  elif [[ -n "$device_id" ]]; then
    device_selection_source="auto"
  else
    device_selection_source="none"
  fi

  if [[ -z "$device_id" && "$unavailable_device_count" != "0" ]]; then
    device_status="unavailable"
    append_unique issue_codes "physical-iphone-device-unavailable"
    append_unique setup_actions "unlock-connect-and-enable-developer-mode"
  elif [[ -n "${NARU_PHYSICAL_IOS_DEVICE_ID:-}" ]] && physical_unavailable_iphone_id_is_known "$device_id"; then
    device_status="unavailable"
    append_unique issue_codes "physical-iphone-device-unavailable"
    append_unique setup_actions "unlock-connect-and-enable-developer-mode"
  elif [[ -z "$device_id" ]]; then
    device_status="missing"
    append_unique issue_codes "physical-iphone-device-missing"
    append_unique setup_actions "connect-and-trust-physical-iphone"
  elif [[ -n "${NARU_PHYSICAL_IOS_DEVICE_ID:-}" ]] && ! physical_ios_device_id_is_iphone "$device_id"; then
    device_status="wrongDeviceType"
    append_unique issue_codes "physical-iphone-device-required"
    append_unique setup_actions "set-physical-ios-device-id-to-iphone"
  elif [[ "$device_count" != "1" && -z "${NARU_PHYSICAL_IOS_DEVICE_ID:-}" ]]; then
    device_status="multiple"
    append_unique issue_codes "physical-iphone-device-ambiguous"
    append_unique setup_actions "set-physical-ios-device-id"
  else
    device_status="connected"
  fi

  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    signing_identity_status="available"
  else
    signing_identity_status="missing"
    append_unique issue_codes "ios-development-certificate-missing"
    append_unique setup_actions "install-ios-development-certificate"
  fi

  if [[ -n "${NARU_XCODE_DEVELOPMENT_TEAM:-}" ]]; then
    development_team_status="environment"
  else
    PHYSICAL_DEVELOPMENT_TEAM_STATUS="missing"
    resolve_physical_development_team
    development_team_status="$PHYSICAL_DEVELOPMENT_TEAM_STATUS"
    if [[ "$development_team_status" == "ambiguous" ]]; then
      append_unique issue_codes "ios-development-team-ambiguous"
      append_unique setup_actions "set-xcode-development-team"
    fi
  fi

  if [[ -z "$device_id" || "$device_status" == "multiple" || "$device_status" == "wrongDeviceType" || "$device_status" == "unavailable" ]]; then
    build_check_status="skipped"
  else
    local output_file
    output_file="$(mktemp "${TMPDIR:-/tmp}/naru-physical-preflight.XXXXXX")"
    build_check_status="$(physical_preflight_build_status "$device_id" "$output_file")"
    if [[ "$build_check_status" == "failed" ]]; then
      if grep -q "requires a development team" "$output_file"; then
        append_unique issue_codes "ios-development-team-missing"
        append_unique setup_actions "set-xcode-development-team"
      fi
      if grep -q "No Accounts" "$output_file"; then
        xcode_account_status="missing"
        append_unique issue_codes "xcode-account-missing"
        append_unique setup_actions "add-xcode-account"
      fi
      if grep -q "No profiles for" "$output_file"; then
        provisioning_profile_status="missing"
        append_unique issue_codes "ios-provisioning-profile-missing"
        append_unique setup_actions "create-ios-development-provisioning-profile"
      fi
      if grep -qi "locked" "$output_file"; then
        append_unique issue_codes "physical-ios-device-locked"
        append_unique setup_actions "unlock-physical-iphone"
      fi
      if ((${#issue_codes[@]} == 0)); then
        append_unique issue_codes "physical-ios-build-failed"
        append_unique setup_actions "inspect-xcode-physical-build"
      fi
    else
      provisioning_profile_status="available"
      xcode_account_status="available"
    fi
    rm -f "$output_file"
  fi

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "mode": "physical-device-preflight",\n'
  printf '  "deviceDiscoveryStatus": "%s",\n' "$device_status"
  printf '  "deviceSelectionSource": "%s",\n' "$device_selection_source"
  printf '  "codeSigningIdentityStatus": "%s",\n' "$signing_identity_status"
  printf '  "developmentTeamStatus": "%s",\n' "$development_team_status"
  printf '  "xcodeAccountStatus": "%s",\n' "$xcode_account_status"
  printf '  "provisioningProfileStatus": "%s",\n' "$provisioning_profile_status"
  printf '  "buildCheckStatus": "%s",\n' "$build_check_status"
  printf '  "issueCodes": '
  if ((${#issue_codes[@]})); then
    json_string_array "${issue_codes[@]}"
  else
    json_string_array
  fi
  printf ',\n'
  printf '  "setupActionLabels": '
  if ((${#setup_actions[@]})); then
    json_string_array "${setup_actions[@]}"
  else
    json_string_array
  fi
  printf '\n}\n'
}

open_screen_recording_settings_status() {
  if [[ "${NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN:-}" == "skip" ]]; then
    printf 'skipped'
    return
  fi

  if ! command -v open >/dev/null 2>&1; then
    printf 'unsupported'
    return
  fi

  if open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" \
    >/dev/null 2>&1; then
    printf 'opened'
  else
    printf 'failed'
  fi
}

helper_dev_app_executable_path() {
  local install_root="${NARU_HELPER_DEV_APP_ROOT:-$HOME/Applications/NaruRemoteDev}"
  printf '%s/NaruHelperDev.app/Contents/MacOS/NaruHelper' "$install_root"
}

helper_dev_app_codesign_status() {
  local helper_executable="$1"
  local app_path
  app_path="$(cd -- "$(dirname -- "$helper_executable")/../.." && pwd 2>/dev/null || true)"
  if [[ -z "$app_path" || ! -e "$app_path/Contents/Info.plist" ]]; then
    printf 'missing'
    return
  fi

  local codesign_output
  if ! codesign_output="$(codesign -dv --verbose=2 "$app_path" 2>&1)"; then
    printf 'invalid'
    return
  fi
  if grep -q '^Authority=Apple Development:' <<<"$codesign_output"; then
    printf 'appleDevelopment'
    return
  fi
  if grep -q '^Signature=adhoc' <<<"$codesign_output"; then
    printf 'adHoc'
    return
  fi
  printf 'other'
}

json_value_or_unknown() {
  local json="$1"
  local filter="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$filter // \"unknown\"" <<<"$json" 2>/dev/null || printf 'unknown'
  else
    printf 'unknown'
  fi
}

print_helper_dev_app_setup_report() {
  local install_output_file
  install_output_file="$(mktemp "${TMPDIR:-/tmp}/naru-helper-dev-app-install.XXXXXX")"
  local helper_executable
  helper_executable="$(helper_dev_app_executable_path)"
  local install_status="failed"
  local issue_codes=()
  local setup_actions=()

  if scripts/install-naru-helper-dev-app.sh --set-launchctl-env \
    >"$install_output_file" 2>&1; then
    install_status="passed"
    export NARU_HELPER_EXECUTABLE="$helper_executable"
  else
    append_unique issue_codes "helper-dev-app-install-failed"
    append_unique setup_actions "inspect-helper-dev-app-install"
  fi
  rm -f "$install_output_file"

  local codesign_status="unknown"
  local launchctl_env_status="notSet"
  local helper_process_kind="unknown"
  local capability_after_install='{"status":"failed","step":"helperCapabilityAfterInstall","safeFailureCode":"benchmarkStep.helperCapabilityAfterInstall.failed"}'
  local permission_request='{"status":"failed","step":"helperPermissionRequest","safeFailureCode":"benchmarkStep.helperPermissionRequest.failed"}'
  local capability_after_request='{"status":"failed","step":"helperCapabilityAfterRequest","safeFailureCode":"benchmarkStep.helperCapabilityAfterRequest.failed"}'
  local settings_open_status="skipped"

  if [[ "$install_status" == "passed" ]]; then
    codesign_status="$(helper_dev_app_codesign_status "$helper_executable")"
    if [[ "$(launchctl getenv NARU_HELPER_EXECUTABLE 2>/dev/null || true)" == "$helper_executable" ]]; then
      launchctl_env_status="set"
    fi
    capability_after_install="$(
      json_step_or_fixed_failure \
        helperCapabilityAfterInstall \
        benchmarkStep.helperCapabilityAfterInstall.failed \
        "$helper_executable" --video-capability
    )"
    helper_process_kind="$(
      json_value_or_unknown \
        "$capability_after_install" \
        '.permissionIdentity.processKind'
    )"
    permission_request="$(
      json_step_or_fixed_failure \
        helperPermissionRequest \
        benchmarkStep.helperPermissionRequest.failed \
        "$helper_executable" --video-request-screen-recording-permission
    )"
    settings_open_status="$(open_screen_recording_settings_status)"
    capability_after_request="$(
      json_step_or_fixed_failure \
        helperCapabilityAfterRequest \
        benchmarkStep.helperCapabilityAfterRequest.failed \
        "$helper_executable" --video-capability
    )"

    local permission_status
    permission_status="$(json_value_or_unknown "$capability_after_request" '.screenRecordingPermission')"
    if [[ "$permission_status" != "granted" ]]; then
      append_unique issue_codes "helper-video-permission-missing"
      append_unique setup_actions "grant-helper-video-app-screen-recording-permission"
      append_unique setup_actions "quit-and-relaunch-helper-after-permission-change"
      append_unique setup_actions "rerun-helper-readiness-sweep"
    fi
  fi

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "mode": "helper-dev-app-setup",\n'
  printf '  "installStatus": '
  json_string "$install_status"
  printf ',\n'
  printf '  "codeSigningStatus": '
  json_string "$codesign_status"
  printf ',\n'
  printf '  "launchctlEnvStatus": '
  json_string "$launchctl_env_status"
  printf ',\n'
  printf '  "helperProcessKind": '
  json_string "$helper_process_kind"
  printf ',\n'
  printf '  "capabilityAfterInstall": %s,\n' "$capability_after_install"
  printf '  "permissionRequest": %s,\n' "$permission_request"
  printf '  "settingsOpenStatus": '
  json_string "$settings_open_status"
  printf ',\n'
  printf '  "capabilityAfterRequest": %s,\n' "$capability_after_request"
  printf '  "issueCodes": '
  json_string_array "${issue_codes[@]}"
  printf ',\n'
  printf '  "setupActionLabels": '
  json_string_array "${setup_actions[@]}"
  printf ',\n'
  printf '  "safety": [\n'
  printf '    "helper executable paths, team identifiers, signing identities, raw install logs, endpoints, credentials, pixels, byte counts, and exact timings are not emitted",\n'
  printf '    "only fixed install/signing/env status labels, helper capability JSON, fixed issue codes, and setup actions are emitted"\n'
  printf '  ]\n'
  printf '}\n'
}

screen_recording_watch_max_polls() {
  local raw="${NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS:-45}"
  if [[ "$raw" =~ ^[0-9]+$ ]] && ((raw >= 1 && raw <= 300)); then
    printf '%s' "$raw"
  else
    printf '45'
  fi
}

screen_recording_watch_interval_seconds() {
  local raw="${NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS:-2}"
  if [[ "$raw" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$raw"
  else
    printf '2'
  fi
}

screen_recording_capability_is_granted() {
  local capability_json="$1"
  local permission
  local availability
  permission="$(json_value_or_unknown "$capability_json" '.screenRecordingPermission')"
  availability="$(json_value_or_unknown "$capability_json" '.availability')"
  [[ "$permission" == "granted" || "$availability" == "available" ]]
}

print_screen_recording_watch_report() {
  local helper_executable="${NARU_HELPER_EXECUTABLE:-}"
  local max_polls
  local interval_seconds
  max_polls="$(screen_recording_watch_max_polls)"
  interval_seconds="$(screen_recording_watch_interval_seconds)"

  local capability_before
  local permission_request
  local settings_open_status
  capability_before="$(
    json_step_or_fixed_failure \
      helperCapabilityBefore \
      benchmarkStep.helperCapabilityBefore.failed \
      "$helper_executable" --video-capability
  )"
  permission_request="$(
    json_step_or_fixed_failure \
      helperPermissionRequest \
      benchmarkStep.helperPermissionRequest.failed \
      "$helper_executable" --video-request-screen-recording-permission
  )"
  settings_open_status="$(open_screen_recording_settings_status)"

  local final_capability="$capability_before"
  local watch_status="timedOut"
  local polls_attempted=0
  local poll
  for ((poll = 1; poll <= max_polls; poll++)); do
    polls_attempted="$poll"
    final_capability="$(
      json_step_or_fixed_failure \
        helperCapabilityPoll \
        benchmarkStep.helperCapabilityPoll.failed \
        "$helper_executable" --video-capability
    )"
    if screen_recording_capability_is_granted "$final_capability"; then
      watch_status="granted"
      break
    fi
    if ((poll < max_polls)); then
      sleep "$interval_seconds"
    fi
  done

  local final_permission_status
  local final_availability
  local final_step_status
  local permission_process_kind
  local permission_grant_hint
  final_permission_status="$(json_value_or_unknown "$final_capability" '.screenRecordingPermission')"
  final_availability="$(json_value_or_unknown "$final_capability" '.availability')"
  final_step_status="$(json_value_or_unknown "$final_capability" '.status')"
  permission_process_kind="$(json_value_or_unknown "$final_capability" '.permissionIdentity.processKind')"
  permission_grant_hint="$(json_value_or_unknown "$final_capability" '.permissionIdentity.grantHint')"

  local issue_codes=()
  local setup_actions=()
  if [[ "$watch_status" == "granted" ]]; then
    append_unique setup_actions "rerun-helper-readiness-sweep"
    append_unique setup_actions "run-true-helper-video-live-capture-benchmark"
  elif [[ "$final_step_status" == "failed" ]]; then
    watch_status="failed"
    append_unique issue_codes "helper-video-capability-failed"
    append_unique setup_actions "inspect-helper-video-capability"
  else
    append_unique issue_codes "helper-video-permission-missing"
    append_unique setup_actions "grant-helper-video-app-screen-recording-permission"
    append_unique setup_actions "quit-and-relaunch-helper-after-permission-change"
    append_unique setup_actions "rerun-screen-recording-watch"
  fi

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "mode": "screen-recording-watch",\n'
  printf '  "watchStatus": '
  json_string "$watch_status"
  printf ',\n'
  printf '  "maxPolls": %s,\n' "$max_polls"
  printf '  "pollIntervalSeconds": '
  json_string "$interval_seconds"
  printf ',\n'
  printf '  "pollsAttempted": %s,\n' "$polls_attempted"
  printf '  "settingsOpenStatus": '
  json_string "$settings_open_status"
  printf ',\n'
  printf '  "capabilityBefore": %s,\n' "$capability_before"
  printf '  "permissionRequest": %s,\n' "$permission_request"
  printf '  "finalCapability": %s,\n' "$final_capability"
  printf '  "finalPermissionStatus": '
  json_string "$final_permission_status"
  printf ',\n'
  printf '  "finalAvailability": '
  json_string "$final_availability"
  printf ',\n'
  printf '  "permissionProcessKind": '
  json_string "$permission_process_kind"
  printf ',\n'
  printf '  "permissionGrantHint": '
  json_string "$permission_grant_hint"
  printf ',\n'
  printf '  "postPermissionChangeRequiresRelaunch": true,\n'
  printf '  "issueCodes": '
  if ((${#issue_codes[@]})); then
    json_string_array "${issue_codes[@]}"
  else
    json_string_array
  fi
  printf ',\n'
  printf '  "setupActionLabels": '
  if ((${#setup_actions[@]})); then
    json_string_array "${setup_actions[@]}"
  else
    json_string_array
  fi
  printf ',\n'
  printf '  "safety": [\n'
  printf '    "screen-recording-watch emits fixed status, issue, and action labels plus helper safe capability JSON only",\n'
  printf '    "helper executable paths, endpoints, credentials, raw OS errors, pixels, dimensions, byte counts, and exact helper timings are not emitted"\n'
  printf '  ]\n'
  printf '}\n'
}

screen_recording_watch_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/naru-screen-recording-watch-test.XXXXXX")"
  local fake_helper="$tmpdir/fake-helper"
  local state_file="$tmpdir/state"
  cat >"$fake_helper" <<'FAKE_HELPER'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --video-capability)
    count="$(cat "$NARU_FAKE_HELPER_STATE" 2>/dev/null || printf '0')"
    count=$((count + 1))
    printf '%s' "$count" >"$NARU_FAKE_HELPER_STATE"
    if ((count >= 3)); then
      printf '{"schemaVersion":2,"availability":"available","screenRecordingPermission":"granted","permissionIdentity":{"processKind":"appBundle","grantHint":"grantAppBundle"}}\n'
    else
      printf '{"schemaVersion":2,"availability":"permissionMissing","screenRecordingPermission":"missing","permissionIdentity":{"processKind":"appBundle","grantHint":"grantAppBundle"},"safeFailureCode":"helperVideo.permissionMissing"}\n'
    fi
    ;;
  --video-request-screen-recording-permission)
    printf '{"schemaVersion":2,"status":"notGranted","permissionIdentity":{"processKind":"appBundle","grantHint":"grantAppBundle"}}\n'
    ;;
  *)
    exit 2
    ;;
esac
FAKE_HELPER
  chmod +x "$fake_helper"

  local report
  report="$(
    NARU_HELPER_EXECUTABLE="$fake_helper" \
    NARU_FAKE_HELPER_STATE="$state_file" \
    NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
    NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS=4 \
    NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS=0 \
    print_screen_recording_watch_report
  )"
  rm -rf "$tmpdir"

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$report"
    return
  fi

  jq -e '
    .schemaVersion == 1 and
    .mode == "screen-recording-watch" and
    .watchStatus == "granted" and
    .finalPermissionStatus == "granted" and
    .finalAvailability == "available" and
    .permissionProcessKind == "appBundle" and
    .permissionGrantHint == "grantAppBundle" and
    .postPermissionChangeRequiresRelaunch == true and
    .pollsAttempted == 2 and
    (.setupActionLabels | index("rerun-helper-readiness-sweep")) and
    (.setupActionLabels | index("run-true-helper-video-live-capture-benchmark")) and
    (.issueCodes | length == 0)
  ' <<<"$report" >/dev/null
  printf '%s\n' "$report"
}

print_helper_video_live_gate_summary_failure() {
  local failure_code="$1"
  printf '{"schemaVersion":1,"mode":"helper-video-live-gate-summary","overallGateState":"unknown","safeFailureCode":'
  json_string "$failure_code"
  printf ',"primaryBlockedGateLabels":["helper-video-live-gate-summary-unavailable"],"recommendedPrimaryAction":"inspect-helper-video-live-gate"}'
}

print_helper_video_live_gate_summary() {
  local watch_file="$1"
  local readiness_file="$2"
  local bootstrap_file="$3"

  if ! command -v jq >/dev/null 2>&1; then
    print_helper_video_live_gate_summary_failure \
      benchmarkStep.helperVideoLiveGateSummary.jqUnavailable
    return
  fi

  if ! jq -n \
    --slurpfile watch "$watch_file" \
    --slurpfile readiness "$readiness_file" \
    --slurpfile bootstrap "$bootstrap_file" '
      def first($items): $items[0] // {};
      def hreport($key):
        (first($readiness)[$key].visualTransportComparison.helperVideoReports[0] // {});
      def watch_status: first($watch).watchStatus // "unknown";
      def final_permission: first($watch).finalPermissionStatus // "unknown";
      def final_availability: first($watch).finalAvailability // "unknown";
      def screen_verdict: hreport("screenProbe").verdict // "unknown";
      def synthetic_verdict: hreport("syntheticProbe").verdict // "unknown";
      def sustained_verdict: hreport("sustainedSyntheticProbe").verdict // "unknown";
      def bootstrap_status: first($bootstrap).status // "unknown";
      def blocked_labels:
        [
          if watch_status != "granted" then "screen-recording-permission-gate-blocked" else empty end,
          if watch_status == "granted" and synthetic_verdict != "pass" then "helper-video-synthetic-gate-blocked" else empty end,
          if watch_status == "granted" and sustained_verdict != "pass" then "helper-video-sustained-synthetic-gate-blocked" else empty end,
          if watch_status == "granted" and screen_verdict != "pass" then "helper-video-screen-capture-gate-blocked" else empty end,
          if watch_status == "granted" and screen_verdict == "pass" and bootstrap_status == "skipped" then "helper-video-app-bootstrap-skipped" else empty end,
          if watch_status == "granted" and screen_verdict == "pass" and bootstrap_status == "failed" then "helper-video-app-bootstrap-failed" else empty end
        ];
      def overall_gate_state:
        if watch_status != "granted" then "blockedByScreenRecordingPermission"
        elif synthetic_verdict != "pass" then "blockedByHelperSyntheticTransport"
        elif sustained_verdict != "pass" then "blockedByHelperSustainedSyntheticTransport"
        elif screen_verdict != "pass" then "blockedByHelperScreenCapture"
        elif bootstrap_status == "passed" then "readyForPhysicalIPhoneGate"
        elif bootstrap_status == "skipped" then "blockedByAppBootstrapPermission"
        elif bootstrap_status == "failed" then "blockedByAppBootstrapBenchmark"
        else "unknown"
        end;
      def recommended_action:
        if watch_status != "granted" then "grant-helper-video-app-screen-recording-permission"
        elif synthetic_verdict != "pass" then "inspect-helper-video-synthetic-transport"
        elif sustained_verdict != "pass" then "inspect-helper-video-sustained-cadence"
        elif screen_verdict != "pass" then "rerun-helper-screen-probe"
        elif bootstrap_status == "passed" then "run-physical-iphone-helper-video-gate"
        elif bootstrap_status == "skipped" then "grant-screen-recording-to-benchmark-host"
        elif bootstrap_status == "failed" then "inspect-screen-capturekit-app-bootstrap-benchmark"
        else "inspect-helper-video-live-gate"
        end;
      {
        schemaVersion: 1,
        mode: "helper-video-live-gate-summary",
        overallGateState: overall_gate_state,
        primaryBlockedGateLabels: blocked_labels,
        recommendedPrimaryAction: recommended_action,
        screenRecordingGate: {
          watchStatus: watch_status,
          finalPermissionStatus: final_permission,
          finalAvailability: final_availability,
          issueCodes: (first($watch).issueCodes // []),
          setupActionLabels: (first($watch).setupActionLabels // [])
        },
        helperVideoGate: {
          syntheticVerdict: synthetic_verdict,
          sustainedSyntheticVerdict: sustained_verdict,
          screenCaptureVerdict: screen_verdict,
          screenCaptureReadinessState: (hreport("screenProbe").readinessState // "unknown"),
          screenCaptureRecommendedAction: (hreport("screenProbe").recommendedAction // "unknown"),
          screenCaptureIssueCodes: (hreport("screenProbe").issueCodes // [])
        },
        appBootstrapGate: {
          status: bootstrap_status,
          sourceMode: (first($bootstrap).sourceMode // "unknown"),
          transportPath: (first($bootstrap).transportPath // "unknown"),
          decodePath: (first($bootstrap).decodePath // "unknown"),
          issueCodes: (first($bootstrap).issueCodes // []),
          setupActionLabels: (first($bootstrap).setupActionLabels // [])
        },
        diagnosticDesignLabels: [
          "screen-recording-watch-precedes-true-helper-video-gates",
          "permission-missing-skips-expensive-helper-video-gates",
          "helper-readiness-and-app-bootstrap-share-one-report",
          "ready-state-routes-to-physical-iphone-gate"
        ]
      }
    ' >/dev/stdout; then
    print_helper_video_live_gate_summary_failure \
      benchmarkStep.helperVideoLiveGateSummary.failed
  fi
}

print_helper_video_live_gate_skipped_readiness() {
  printf '{'
  printf '"schemaVersion":1,'
  printf '"mode":"helper-readiness-sweep",'
  printf '"status":"skipped",'
  printf '"skipReason":"screenRecordingPermissionMissing",'
  printf '"issueCodes":["helper-video-permission-missing"],'
  printf '"setupActionLabels":["grant-helper-video-app-screen-recording-permission","rerun-helper-video-live-gate"],'
  printf '"safety":["readiness sweep skipped before helper capture; no helper paths, endpoints, credentials, pixels, byte counts, dimensions, raw OS errors, or exact timings are emitted"]'
  printf '}'
}

print_helper_video_live_gate_skipped_bootstrap() {
  printf '{'
  printf '"schemaVersion":1,'
  printf '"mode":"helper-screen-app-bootstrap-benchmark",'
  printf '"status":"skipped",'
  printf '"sourceMode":"screen-capturekit",'
  printf '"transportPath":"helper-tcp-to-app-model",'
  printf '"decodePath":"h264-sample-buffer-factory",'
  printf '"skipReason":"screenRecordingPermissionMissing",'
  printf '"issueCodes":["helper-video-permission-missing"],'
  printf '"setupActionLabels":["grant-helper-video-app-screen-recording-permission","rerun-helper-video-live-gate"],'
  printf '"safety":["app bootstrap skipped before helper capture; no raw xctest output, frame payloads, pixels, dimensions, endpoints, helper paths, device ids, credentials, byte counts, or exact timings are emitted"]'
  printf '}'
}

print_helper_video_live_gate_report() {
  local watch_file
  local readiness_file
  local bootstrap_file
  watch_file="$(mktemp "${TMPDIR:-/tmp}/naru-helper-live-watch.XXXXXX")"
  readiness_file="$(mktemp "${TMPDIR:-/tmp}/naru-helper-live-readiness.XXXXXX")"
  bootstrap_file="$(mktemp "${TMPDIR:-/tmp}/naru-helper-live-bootstrap.XXXXXX")"

  json_step_or_fixed_failure \
    screenRecordingWatch \
    benchmarkStep.screenRecordingWatch.failed \
    print_screen_recording_watch_report >"$watch_file"

  local watch_status
  watch_status="$(json_value_or_unknown "$(cat "$watch_file")" '.watchStatus')"
  if [[ "$watch_status" == "granted" ]]; then
    json_step_or_fixed_failure \
      helperReadinessSweep \
      benchmarkStep.helperReadinessSweep.failed \
      print_helper_readiness_sweep_report >"$readiness_file"
    json_step_or_fixed_failure \
      helperScreenAppBootstrapBenchmark \
      benchmarkStep.helperScreenAppBootstrapBenchmark.failed \
      print_helper_screen_app_bootstrap_benchmark_report >"$bootstrap_file"
  else
    print_helper_video_live_gate_skipped_readiness >"$readiness_file"
    print_helper_video_live_gate_skipped_bootstrap >"$bootstrap_file"
  fi

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "mode": "helper-video-live-gate",\n'
  printf '  "screenRecordingWatch": '
  cat "$watch_file"
  printf ',\n'
  printf '  "helperReadinessSweep": '
  cat "$readiness_file"
  printf ',\n'
  printf '  "appBootstrapBenchmark": '
  cat "$bootstrap_file"
  printf ',\n'
  printf '  "gateSummary": '
  print_helper_video_live_gate_summary \
    "$watch_file" \
    "$readiness_file" \
    "$bootstrap_file"
  printf ',\n'
  printf '  "safety": [\n'
  printf '    "helper-video-live-gate emits fixed status, issue, action, and transport labels plus existing safe subreports only",\n'
  printf '    "helper executable paths, endpoints, credentials, raw OS errors, pixels, dimensions, byte counts, physical device ids, raw xctest output, and exact helper timings are not emitted"\n'
  printf '  ]\n'
  printf '}\n'

  rm -f "$watch_file" "$readiness_file" "$bootstrap_file"
}

helper_video_live_gate_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/naru-helper-live-gate-test.XXXXXX")"
  local watch_blocked="$tmpdir/watch-blocked.json"
  local watch_ready="$tmpdir/watch-ready.json"
  local readiness_blocked="$tmpdir/readiness-blocked.json"
  local readiness_ready="$tmpdir/readiness-ready.json"
  local bootstrap_blocked="$tmpdir/bootstrap-blocked.json"
  local bootstrap_ready="$tmpdir/bootstrap-ready.json"
  local summary_blocked="$tmpdir/summary-blocked.json"
  local summary_ready="$tmpdir/summary-ready.json"

  cat >"$watch_blocked" <<'JSON'
{"schemaVersion":1,"mode":"screen-recording-watch","watchStatus":"timedOut","finalPermissionStatus":"missing","finalAvailability":"permissionMissing","issueCodes":["helper-video-permission-missing"],"setupActionLabels":["grant-helper-video-app-screen-recording-permission","rerun-screen-recording-watch"]}
JSON
  cat >"$watch_ready" <<'JSON'
{"schemaVersion":1,"mode":"screen-recording-watch","watchStatus":"granted","finalPermissionStatus":"granted","finalAvailability":"available","issueCodes":[],"setupActionLabels":["rerun-helper-readiness-sweep","run-true-helper-video-live-capture-benchmark"]}
JSON
  print_helper_video_live_gate_skipped_readiness >"$readiness_blocked"
  print_helper_video_live_gate_skipped_bootstrap >"$bootstrap_blocked"
  cat >"$readiness_ready" <<'JSON'
{"schemaVersion":1,"mode":"helper-readiness-sweep","syntheticProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}},"sustainedSyntheticProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}},"screenProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}}}
JSON
  cat >"$bootstrap_ready" <<'JSON'
{"schemaVersion":1,"mode":"helper-screen-app-bootstrap-benchmark","status":"passed","sourceMode":"screen-capturekit","transportPath":"helper-tcp-to-app-model","decodePath":"h264-sample-buffer-factory","issueCodes":[],"setupActionLabels":[]}
JSON

  print_helper_video_live_gate_summary \
    "$watch_blocked" \
    "$readiness_blocked" \
    "$bootstrap_blocked" >"$summary_blocked"
  print_helper_video_live_gate_summary \
    "$watch_ready" \
    "$readiness_ready" \
    "$bootstrap_ready" >"$summary_ready"

  if ! command -v jq >/dev/null 2>&1; then
    printf '{"schemaVersion":1,"mode":"helper-video-live-gate-self-test","status":"skipped","issueCodes":["jq-unavailable"]}\n'
    rm -rf "$tmpdir"
    return
  fi

  if jq -e '
    .overallGateState == "blockedByScreenRecordingPermission" and
    .recommendedPrimaryAction == "grant-helper-video-app-screen-recording-permission" and
    (.primaryBlockedGateLabels | index("screen-recording-permission-gate-blocked")) and
    .screenRecordingGate.finalPermissionStatus == "missing" and
    .appBootstrapGate.status == "skipped"
  ' "$summary_blocked" >/dev/null && jq -e '
    .overallGateState == "readyForPhysicalIPhoneGate" and
    .recommendedPrimaryAction == "run-physical-iphone-helper-video-gate" and
    (.primaryBlockedGateLabels | length == 0) and
    .screenRecordingGate.finalPermissionStatus == "granted" and
    .helperVideoGate.screenCaptureVerdict == "pass" and
    .appBootstrapGate.status == "passed"
  ' "$summary_ready" >/dev/null; then
    printf '{"schemaVersion":1,"mode":"helper-video-live-gate-self-test","status":"passed","blockedSummary":'
    cat "$summary_blocked"
    printf ',"readySummary":'
    cat "$summary_ready"
    printf '}\n'
  else
    printf '{"schemaVersion":1,"mode":"helper-video-live-gate-self-test","status":"failed","blockedSummary":'
    cat "$summary_blocked"
    printf ',"readySummary":'
    cat "$summary_ready"
    printf '}\n'
    rm -rf "$tmpdir"
    exit 1
  fi

  rm -rf "$tmpdir"
}

print_helper_readiness_sweep_report() {
  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "mode": "helper-readiness-sweep",\n'
  printf '  "capability": '
  json_step_or_fixed_failure \
    helperCapability \
    benchmarkStep.helperCapability.failed \
    "$NARU_HELPER_EXECUTABLE" --video-capability
  printf ',\n'
  printf '  "preflight": '
  json_step_or_fixed_failure \
    environmentPreflight \
    benchmarkStep.environmentPreflight.failed \
    swift run --quiet VNCLiveBenchmark \
    --environment-preflight \
    --visual-transport helper-video \
    --helper-video-probe external-helper-screen-capturekit-tcp \
    --json
  printf ',\n'
  printf '  "syntheticProbe": '
  json_step_or_fixed_failure \
    externalSyntheticProbe \
    benchmarkStep.externalSyntheticProbe.failed \
    swift run --quiet VNCLiveBenchmark \
    --helper-video-probe-only \
    --visual-transport helper-video \
    --helper-video-probe external-helper-synthetic-encoded-tcp \
    --json
  printf ',\n'
  printf '  "sustainedSyntheticProbe": '
  json_step_or_fixed_failure \
    externalSustainedSyntheticProbe \
    benchmarkStep.externalSustainedSyntheticProbe.failed \
    swift run --quiet VNCLiveBenchmark \
    --helper-video-probe-only \
    --visual-transport helper-video \
    --helper-video-probe external-helper-sustained-synthetic-encoded-tcp \
    --json
  printf ',\n'
  printf '  "screenProbe": '
  json_step_or_fixed_failure \
    externalScreenCaptureKitProbe \
    benchmarkStep.externalScreenCaptureKitProbe.failed \
    swift run --quiet VNCLiveBenchmark \
    --helper-video-probe-only \
    --visual-transport helper-video \
    --helper-video-probe external-helper-screen-capturekit-tcp \
    --json
  printf '\n}\n'
}

print_helper_screen_app_bootstrap_benchmark_report() {
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-helper-screen-app-bootstrap.XXXXXX")"
  local result_status="failed"
  local issue_codes=()
  local setup_actions=()

  if NARU_RUN_SIM_BENCHMARKS=1 \
    NARU_SIM_BENCHMARK_ITERATIONS=1 \
    NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES=2 \
    swift test --filter \
      HelperVideoAppRunnerBenchmarkTests/testNetworkBackedScreenCaptureKitHelperVideoBootstrapThroughAppModelSmoke \
      >"$output_file" 2>&1; then
    if grep -q "Test skipped -" "$output_file"; then
      result_status="skipped"
      issue_codes=("screen-capturekit-app-bootstrap-skipped")
      setup_actions=("grant-screen-recording-to-benchmark-host" "rerun-helper-screen-app-bootstrap-benchmark")
    else
      result_status="passed"
    fi
  else
    result_status="failed"
    issue_codes=("screen-capturekit-app-bootstrap-failed")
    setup_actions=("inspect-screen-capturekit-app-bootstrap-benchmark")
  fi
  rm -f "$output_file"

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "mode": "helper-screen-app-bootstrap-benchmark",\n'
  printf '  "status": '
  json_string "$result_status"
  printf ',\n'
  printf '  "sourceMode": "screen-capturekit",\n'
  printf '  "transportPath": "helper-tcp-to-app-model",\n'
  printf '  "decodePath": "h264-sample-buffer-factory",\n'
  printf '  "iterationCount": 1,\n'
  printf '  "requestedFrameCount": 2,\n'
  printf '  "issueCodes": '
  json_string_array "${issue_codes[@]}"
  printf ',\n'
  printf '  "setupActionLabels": '
  json_string_array "${setup_actions[@]}"
  printf ',\n'
  printf '  "safety": [\n'
  printf '    "raw xctest output is not emitted",\n'
  printf '    "frame payloads, pixels, dimensions, endpoints, helper paths, device ids, credentials, byte counts, and exact timings are not emitted",\n'
  printf '    "only fixed benchmark labels, status labels, counts, issue codes, and setup action labels are emitted"\n'
  printf '  ]\n'
  printf '}\n'
}

print_remote_desktop_10fps_readiness_summary_failure() {
  local failure_code="$1"
  printf '{"schemaVersion":1,"mode":"remote-desktop-10fps-readiness-gate-summary","overallGateState":"unknown","safeFailureCode":'
  json_string "$failure_code"
  printf ',"primaryBlockedGateLabels":["readiness-summary-unavailable"],"recommendedPrimaryAction":"inspect-readiness-summary"}'
}

print_remote_desktop_10fps_readiness_gate_summary() {
  local physical_file="$1"
  local helper_file="$2"
  local vnc_file="$3"

  if ! command -v jq >/dev/null 2>&1; then
    print_remote_desktop_10fps_readiness_summary_failure \
      benchmarkStep.remoteDesktop10fpsReadinessSummary.jqUnavailable
    return
  fi

  if ! jq -n \
    --slurpfile physical "$physical_file" \
    --slurpfile helper "$helper_file" \
    --slurpfile vnc "$vnc_file" '
      def first($items): $items[0] // {};
      def hreport($key):
        (first($helper)[$key].visualTransportComparison.helperVideoReports[0] // {});
      def vnc_report: first($vnc).report // {};
      def vnc_summary: vnc_report.streamShapeProbe.summary // {};
      def vnc_assessment: vnc_summary.practicalAssessment // {};
      def latency($key): (vnc_summary[$key] // {});
      def physical_status: first($physical).deviceDiscoveryStatus // "unknown";
      def helper_synthetic_verdict: hreport("syntheticProbe").verdict // "unknown";
      def helper_sustained_verdict: hreport("sustainedSyntheticProbe").verdict // "unknown";
      def helper_screen_verdict: hreport("screenProbe").verdict // "unknown";
      def vnc_wrapper_status: first($vnc).status // "unknown";
      def vnc_product_verdict: vnc_assessment.verdict // "unknown";
      def server_cadence: vnc_report.streamShapeServerCadenceDiagnosis.status // "unknown";
      def blocked_labels:
        [
          if physical_status != "connected" then "physical-iphone-gate-blocked" else empty end,
          if helper_synthetic_verdict != "pass" then "helper-video-synthetic-gate-blocked" else empty end,
          if helper_sustained_verdict != "pass" then "helper-video-sustained-synthetic-gate-blocked" else empty end,
          if helper_screen_verdict != "pass" then "helper-video-screen-capture-gate-blocked" else empty end,
          if vnc_product_verdict != "pass" then "vnc-10fps-product-gate-failed" else empty end
        ];
      def overall_gate_state:
        if helper_screen_verdict != "pass" then "blockedByHelperScreenCapture"
        elif helper_synthetic_verdict != "pass" then "blockedByHelperSyntheticTransport"
        elif helper_sustained_verdict != "pass" then "blockedByHelperSustainedSyntheticTransport"
        elif vnc_product_verdict != "pass" then "vncFailedHelperVideoReadyForLiveGate"
        elif physical_status != "connected" then "blockedByPhysicalIPhone"
        else "vnc10fpsReady"
        end;
      def recommended_action:
        if helper_screen_verdict != "pass" then "grant-helper-video-app-screen-recording-permission"
        elif helper_synthetic_verdict != "pass" then "inspect-helper-video-synthetic-transport"
        elif helper_sustained_verdict != "pass" then "inspect-helper-video-sustained-cadence"
        elif vnc_product_verdict != "pass" then "run-true-helper-video-live-capture-benchmark"
        elif physical_status != "connected" then "resolve-physical-iphone-preflight"
        else "run-physical-iphone-helper-video-gate"
        end;
      {
        schemaVersion: 1,
        parentReadinessSchemaVersion: 2,
        mode: "remote-desktop-10fps-readiness-gate-summary",
        overallGateState: overall_gate_state,
        primaryBlockedGateLabels: blocked_labels,
        recommendedPrimaryAction: recommended_action,
        physicalIPhoneGate: {
          status: physical_status,
          issueCodes: (first($physical).issueCodes // []),
          setupActionLabels: (first($physical).setupActionLabels // [])
        },
        helperVideoGate: {
          syntheticVerdict: helper_synthetic_verdict,
          sustainedSyntheticVerdict: helper_sustained_verdict,
          screenCaptureVerdict: helper_screen_verdict,
          sustainedSyntheticReadinessState: (hreport("sustainedSyntheticProbe").readinessState // "unknown"),
          sustainedSyntheticRecommendedAction: (hreport("sustainedSyntheticProbe").recommendedAction // "unknown"),
          screenCaptureReadinessState: (hreport("screenProbe").readinessState // "unknown"),
          screenCaptureRecommendedAction: (hreport("screenProbe").recommendedAction // "unknown"),
          screenCaptureIssueCodes: (hreport("screenProbe").issueCodes // []),
          capabilityAvailability: (first($helper).capability.availability // "unknown"),
          screenRecordingPermission: (
            first($helper).capability.screenRecordingPermission //
            first($helper).preflight.helperVideoScreenCapturePermissionStatus //
            "unknown"
          )
        },
        vnc10fpsGate: {
          wrapperStatus: vnc_wrapper_status,
          productVerdict: vnc_product_verdict,
          primaryIssueCode: (vnc_assessment.primaryIssueCode // "unknown"),
          primaryConstraint: (vnc_assessment.primaryConstraint // "unknown"),
          serverCadenceStatus: server_cadence,
          contentFramesPerSecond: (vnc_summary.contentFramesPerSecond // null),
          averageUpdateMilliseconds: (latency("updateLatency").averageMilliseconds // null),
          p95UpdateMilliseconds: (latency("updateLatency").p95Milliseconds // null),
          firstByteWaitP95Milliseconds: (latency("firstByteWaitLatency").p95Milliseconds // null),
          payloadReadP95Milliseconds: (latency("payloadReadLatency").p95Milliseconds // null),
          clientProcessingP95Milliseconds: (latency("clientProcessingLatency").p95Milliseconds // null)
        },
        diagnosticDesignLabels: [
          "outer-step-status-is-not-product-verdict",
          "physical-helper-vnc-gates-share-one-report",
          "first-byte-wait-routes-to-helper-video-not-profile-promotion",
          "helper-screen-capture-permission-precedes-physical-iphone-gate",
          "sustained-synthetic-helper-video-precedes-physical-iphone-gate",
          "screen-capture-permission-blocks-true-helper-video-live-gate"
        ]
      }
    ' >/dev/stdout; then
    print_remote_desktop_10fps_readiness_summary_failure \
      benchmarkStep.remoteDesktop10fpsReadinessSummary.failed
  fi
}

remote_desktop_readiness_summary_self_test() {
  reject_extra_args

  local physical_file
  local helper_file
  local vnc_file
  local summary_file
  local sustained_blocked_helper_file
  local sustained_blocked_summary_file
  local readiness_file
  physical_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-physical.XXXXXX")"
  helper_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-helper.XXXXXX")"
  vnc_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-vnc.XXXXXX")"
  summary_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-summary.XXXXXX")"
  sustained_blocked_helper_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-helper-sustained.XXXXXX")"
  sustained_blocked_summary_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-summary-sustained.XXXXXX")"
  readiness_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-contract.XXXXXX")"

  cat >"$physical_file" <<'JSON'
{"schemaVersion":1,"mode":"physical-device-preflight","deviceDiscoveryStatus":"unavailable","issueCodes":["physical-iphone-device-unavailable"],"setupActionLabels":["unlock-connect-and-enable-developer-mode"]}
JSON
  cat >"$helper_file" <<'JSON'
{"schemaVersion":1,"mode":"helper-readiness-sweep","capability":{"availability":"permissionMissing","screenRecordingPermission":"missing"},"syntheticProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}},"sustainedSyntheticProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}},"screenProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"fail","issueCodes":["helper-video-permission-missing"],"readinessState":"permissionBlocked","recommendedAction":"grant-helper-video-app-screen-recording-permission"}]}}}
JSON
  cat >"$sustained_blocked_helper_file" <<'JSON'
{"schemaVersion":1,"mode":"helper-readiness-sweep","capability":{"availability":"available","screenRecordingPermission":"granted"},"syntheticProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}},"sustainedSyntheticProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"fail","issueCodes":["helper-video-sustained-choppy"],"readinessState":"sustainedDegraded","recommendedAction":"inspect-helper-video-sustained-cadence"}]}},"screenProbe":{"visualTransportComparison":{"helperVideoReports":[{"schemaVersion":2,"verdict":"pass","issueCodes":[],"readinessState":"readyForPhysicalGate","recommendedAction":"run-physical-iphone-helper-video-gate"}]}}}
JSON
  cat >"$vnc_file" <<'JSON'
{"schemaVersion":1,"mode":"glance-025-10fps-duration-probe","status":"passed","report":{"streamShapeServerCadenceDiagnosis":{"status":"first-byte-wait-dominated"},"streamShapeProbe":{"summary":{"contentFramesPerSecond":1.9,"updateLatency":{"averageMilliseconds":503,"p95Milliseconds":632},"firstByteWaitLatency":{"p95Milliseconds":630},"payloadReadLatency":{"p95Milliseconds":0},"clientProcessingLatency":{"p95Milliseconds":2},"practicalAssessment":{"verdict":"fail","primaryIssueCode":"first-byte-wait-failed","primaryConstraint":"receivePath"}}}}}
JSON

  print_remote_desktop_10fps_readiness_gate_summary \
    "$physical_file" \
    "$helper_file" \
    "$vnc_file" >"$summary_file"
  print_remote_desktop_10fps_readiness_gate_summary \
    "$physical_file" \
    "$sustained_blocked_helper_file" \
    "$vnc_file" >"$sustained_blocked_summary_file"

  {
    printf '{"schemaVersion":2,"mode":"remote-desktop-10fps-readiness","physicalDevicePreflight":'
    cat "$physical_file"
    printf ',"helperReadinessSweep":'
    cat "$helper_file"
    printf ',"vnc10fpsProbe":'
    cat "$vnc_file"
    printf ',"readinessGateSummary":'
    cat "$summary_file"
    printf '}'
  } >"$readiness_file"

  if jq -e '
    .schemaVersion == 2 and
    .mode == "remote-desktop-10fps-readiness" and
    has("physicalDevicePreflight") and
    has("helperReadinessSweep") and
    has("vnc10fpsProbe") and
    has("readinessGateSummary") and
    .readinessGateSummary.schemaVersion == 1 and
    .readinessGateSummary.parentReadinessSchemaVersion == 2 and
    .readinessGateSummary.overallGateState == "blockedByHelperScreenCapture" and
    .readinessGateSummary.recommendedPrimaryAction == "grant-helper-video-app-screen-recording-permission" and
    (.readinessGateSummary.primaryBlockedGateLabels | index("physical-iphone-gate-blocked")) and
    (.readinessGateSummary.primaryBlockedGateLabels | index("helper-video-screen-capture-gate-blocked")) and
    (.readinessGateSummary.primaryBlockedGateLabels | index("vnc-10fps-product-gate-failed")) and
    .readinessGateSummary.vnc10fpsGate.productVerdict == "fail" and
    .readinessGateSummary.vnc10fpsGate.serverCadenceStatus == "first-byte-wait-dominated" and
    .readinessGateSummary.helperVideoGate.sustainedSyntheticVerdict == "pass" and
    .readinessGateSummary.helperVideoGate.screenCaptureReadinessState == "permissionBlocked" and
    .readinessGateSummary.helperVideoGate.screenCaptureRecommendedAction == "grant-helper-video-app-screen-recording-permission" and
    .readinessGateSummary.helperVideoGate.screenRecordingPermission == "missing"
  ' "$readiness_file" >/dev/null && jq -e '
    .overallGateState == "blockedByHelperSustainedSyntheticTransport" and
    .recommendedPrimaryAction == "inspect-helper-video-sustained-cadence" and
    (.primaryBlockedGateLabels | index("helper-video-sustained-synthetic-gate-blocked")) and
    (.primaryBlockedGateLabels | index("vnc-10fps-product-gate-failed")) and
    .helperVideoGate.sustainedSyntheticVerdict == "fail" and
    .helperVideoGate.sustainedSyntheticReadinessState == "sustainedDegraded" and
    .helperVideoGate.sustainedSyntheticRecommendedAction == "inspect-helper-video-sustained-cadence" and
    .helperVideoGate.screenCaptureVerdict == "pass" and
    .helperVideoGate.screenRecordingPermission == "granted"
  ' "$sustained_blocked_summary_file" >/dev/null; then
    printf '{"schemaVersion":1,"mode":"remote-desktop-readiness-summary-self-test","status":"passed","summary":'
    cat "$summary_file"
    printf ',"sustainedBlockedSummary":'
    cat "$sustained_blocked_summary_file"
    printf '}\n'
  else
    printf '{"schemaVersion":1,"mode":"remote-desktop-readiness-summary-self-test","status":"failed","summary":'
    cat "$summary_file"
    printf ',"sustainedBlockedSummary":'
    cat "$sustained_blocked_summary_file"
    printf '}\n'
    rm -f "$physical_file" "$helper_file" "$vnc_file" "$summary_file" \
      "$sustained_blocked_helper_file" "$sustained_blocked_summary_file" \
      "$readiness_file"
    exit 1
  fi

  rm -f "$physical_file" "$helper_file" "$vnc_file" "$summary_file" \
    "$sustained_blocked_helper_file" "$sustained_blocked_summary_file" \
    "$readiness_file"
}

remote_desktop_10fps_readiness() {
  reject_extra_args
  import_helper_env
  import_live_env
  import_physical_device_env
  cd "$repo_root"

  local physical_file
  local helper_file
  local vnc_file
  physical_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-physical.XXXXXX")"
  helper_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-helper.XXXXXX")"
  vnc_file="$(mktemp "${TMPDIR:-/tmp}/naru-readiness-vnc.XXXXXX")"

  json_step_or_fixed_failure \
    physicalDevicePreflight \
    benchmarkStep.physicalDevicePreflight.failed \
    physical_preflight >"$physical_file"
  json_step_or_fixed_failure \
    helperReadinessSweep \
    benchmarkStep.helperReadinessSweep.failed \
    print_helper_readiness_sweep_report >"$helper_file"
  json_step_or_fixed_failure \
    remoteDesktop10fpsProbe \
    benchmarkStep.remoteDesktop10fpsProbe.failed \
    run_glance_025_10fps_duration_probe >"$vnc_file"

  printf '{\n'
  printf '  "schemaVersion": 2,\n'
  printf '  "mode": "remote-desktop-10fps-readiness",\n'
  printf '  "targetLabel": "iphone-remote-desktop-10fps-v1",\n'
  printf '  "minimumContentFPS": 10,\n'
  printf '  "promotionPolicyLabels": [\n'
  printf '    "vnc-below-10fps-is-product-failure",\n'
  printf '    "helper-video-is-primary-smoothness-candidate",\n'
  printf '    "physical-iphone-gate-required-before-default-promotion"\n'
  printf '  ],\n'
  printf '  "physicalDevicePreflight": '
  cat "$physical_file"
  printf ',\n'
  printf '  "helperReadinessSweep": '
  cat "$helper_file"
  printf ',\n'
  printf '  "vnc10fpsProbe": '
  cat "$vnc_file"
  printf ',\n'
  printf '  "readinessGateSummary": '
  print_remote_desktop_10fps_readiness_gate_summary \
    "$physical_file" \
    "$helper_file" \
    "$vnc_file"
  printf ',\n'
  printf '  "nextActionLabels": [\n'
  printf '    "grant-helper-video-app-screen-recording-permission",\n'
  printf '    "rerun-helper-screen-probe",\n'
  printf '    "run-true-helper-video-live-capture-benchmark",\n'
  printf '    "resolve-physical-iphone-preflight",\n'
  printf '    "run-physical-iphone-helper-video-gate"\n'
  printf '  ]\n'
  printf '}\n'

  rm -f "$physical_file" "$helper_file" "$vnc_file"
}

case "$mode" in
  preflight)
    import_helper_env
    import_optional_live_env
    run_benchmark_with_extra \
      --environment-preflight \
      --visual-transport helper-video \
      --helper-video-probe external-helper-screen-capturekit-tcp \
      --json
    ;;
  helper-synthetic-probe)
    import_helper_env
    cd "$repo_root"
    run_benchmark_with_extra \
      --helper-video-probe-only \
      --visual-transport helper-video \
      --helper-video-probe external-helper-synthetic-encoded-tcp \
      --json
    ;;
  helper-sustained-synthetic-probe)
    import_helper_env
    cd "$repo_root"
    run_benchmark_with_extra \
      --helper-video-probe-only \
      --visual-transport helper-video \
      --helper-video-probe external-helper-sustained-synthetic-encoded-tcp \
      --json
    ;;
  helper-screen-probe)
    import_helper_env
    cd "$repo_root"
    run_benchmark_with_extra \
      --helper-video-probe-only \
      --visual-transport helper-video \
      --helper-video-probe external-helper-screen-capturekit-tcp \
      --json
    ;;
  helper-readiness-sweep)
    reject_extra_args
    import_helper_env
    import_optional_live_env
    cd "$repo_root"
    print_helper_readiness_sweep_report
    ;;
  helper-dev-app-setup)
    reject_extra_args
    cd "$repo_root"
    print_helper_dev_app_setup_report
    ;;
  helper-screen-app-bootstrap-benchmark)
    reject_extra_args
    cd "$repo_root"
    print_helper_screen_app_bootstrap_benchmark_report
    ;;
  helper-video-live-gate)
    reject_extra_args
    import_helper_env
    cd "$repo_root"
    print_helper_video_live_gate_report
    ;;
  helper-video-live-gate-self-test)
    reject_extra_args
    helper_video_live_gate_self_test
    ;;
  short-live-comparison)
    import_helper_env
    import_live_env
    cd "$repo_root"
    run_benchmark_with_extra \
      --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
      --visual-transport vnc,helper-video \
      --helper-video-probe external-helper-sustained-synthetic-encoded-tcp \
      --first-frame-profiles none \
      --full-refresh-samples 0 \
      --continuous-update-samples 0 \
      --stream-shape-samples 2 \
      --stream-shape-duration-seconds 3 \
      --json
    ;;
  glance-scale-sweep)
    reject_extra_args
    import_helper_env
    import_live_env
    cd "$repo_root"
    run_glance_scale_sweep
    ;;
  glance-025-duration-probe)
    reject_extra_args
    import_live_env
    cd "$repo_root"
    run_glance_025_duration_probe
    ;;
  glance-025-profile-sweep)
    reject_extra_args
    import_live_env
    cd "$repo_root"
    run_glance_025_profile_sweep
    ;;
  glance-025-10fps-duration-probe)
    reject_extra_args
    import_live_env
    cd "$repo_root"
    run_glance_025_10fps_duration_probe
    ;;
  remote-desktop-10fps-profile-cadence-sweep)
    reject_extra_args
    import_live_env
    cd "$repo_root"
    run_remote_desktop_10fps_profile_cadence_sweep
    ;;
  remote-desktop-10fps-server-cadence-probe)
    reject_extra_args
    import_live_env
    cd "$repo_root"
    run_remote_desktop_10fps_server_cadence_probe
    ;;
  remote-desktop-10fps-transport-cadence-drilldown)
    reject_extra_args
    import_live_env
    cd "$repo_root"
    run_remote_desktop_10fps_transport_cadence_drilldown
    ;;
  remote-desktop-10fps-readiness)
    remote_desktop_10fps_readiness
    ;;
  remote-desktop-readiness-summary-self-test)
    remote_desktop_readiness_summary_self_test
    ;;
  request-pipeline-sweep)
    import_live_env
    reject_extra_flag --stream-shape-request-pipeline-depth
    cd "$repo_root"
    printf '[\n'
    first_report=1
    for depth in 1 2 3; do
      if ((first_report)); then
        first_report=0
      else
        printf ',\n'
      fi
      run_benchmark_with_extra \
        --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
        --visual-transport vnc \
        --first-frame-profiles none \
        --full-refresh-samples 0 \
        --continuous-update-samples 0 \
        --stream-shape-samples 2 \
        --stream-shape-duration-seconds 3 \
        --stream-shape-request-pipeline-depth "$depth" \
        --json
    done
    printf '\n]\n'
    ;;
  bounded-vnc-profile-sweep)
    import_live_env
    reject_bounded_vnc_profile_flags
    cd "$repo_root"
    bounded_args=(
      --attempts 1
      --stream-shape-frame-interval 0.0166666667
      --stream-shape-idle-frame-interval 0.05
      --stream-shape-empty-backoff app
      --stream-shape-power-mode normal
      --stream-shape-client-pressure app
      --stream-shape-viewport-interaction off
      --stream-shape-stimulus external-command
      --stream-shape-stimulus-warmup-seconds 0.25
      --stream-shape-stimulus-frame-interval 0.0833333333
      --stream-shape-preflight-frames 0
      --stream-shape-practical-target iphone-sustained-usability-v2
      --stream-shape-transport request-response
      --stream-shape-profiles tight-first,zrle-compression-0,adaptive-good-full
      --stream-shape-profile-order rotate
      --stream-shape-profile-iterations 1
      --first-frame-profiles none
      --full-refresh-samples 0
      --continuous-update-samples 0
      --stream-shape-samples 1
      --stream-shape-duration-seconds 2
      --timeout 8
      --idle-timeout 2
      --json
    )
    if ((extra_arg_count)); then
      bounded_args+=("${extra_args[@]}")
    fi
    run_bounded_vnc_profile_sweep "${bounded_args[@]}"
    ;;
  bounded-vnc-profile-drilldown)
    import_live_env
    reject_bounded_vnc_profile_flags
    cd "$repo_root"
    run_bounded_vnc_profile_drilldown
    ;;
  bounded-vnc-candidate-stability)
    import_live_env
    reject_bounded_vnc_profile_flags
    cd "$repo_root"
    run_bounded_vnc_candidate_stability
    ;;
  bounded-vnc-tight-cursor-stability)
    import_live_env
    reject_bounded_vnc_profile_flags
    cd "$repo_root"
    run_bounded_vnc_tight_cursor_stability
    ;;
  bounded-vnc-tight-cursor-depth-sweep)
    import_live_env
    reject_bounded_vnc_profile_flags
    cd "$repo_root"
    run_bounded_vnc_tight_cursor_depth_sweep
    ;;
  physical-device-preflight)
    physical_preflight
    ;;
  physical-team-inference-self-test)
    physical_team_inference_self_test
    ;;
  screen-recording-setup)
    reject_extra_args
    import_helper_env
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "mode": "screen-recording-setup",\n'
    printf '  "capabilityBefore": '
    json_step_or_fixed_failure \
      helperCapabilityBefore \
      benchmarkStep.helperCapabilityBefore.failed \
      "$NARU_HELPER_EXECUTABLE" --video-capability
    printf ',\n'
    printf '  "permissionRequest": '
    json_step_or_fixed_failure \
      helperPermissionRequest \
      benchmarkStep.helperPermissionRequest.failed \
      "$NARU_HELPER_EXECUTABLE" --video-request-screen-recording-permission
    printf ',\n'
    printf '  "settingsOpenStatus": "%s",\n' "$(open_screen_recording_settings_status)"
    printf '  "capabilityAfter": '
    json_step_or_fixed_failure \
      helperCapabilityAfter \
      benchmarkStep.helperCapabilityAfter.failed \
      "$NARU_HELPER_EXECUTABLE" --video-capability
    printf ',\n'
    printf '  "nextAction": "rerun-helper-readiness-sweep"\n'
    printf '}\n'
    ;;
  screen-recording-watch)
    reject_extra_args
    import_helper_env
    print_screen_recording_watch_report
    ;;
  screen-recording-watch-self-test)
    reject_extra_args
    screen_recording_watch_self_test
    ;;
  helper-capability)
    reject_extra_args
    import_helper_env
    "$NARU_HELPER_EXECUTABLE" --video-capability
    ;;
  request-screen-recording)
    reject_extra_args
    import_helper_env
    "$NARU_HELPER_EXECUTABLE" --video-request-screen-recording-permission
    ;;
  *)
    printf 'Unknown mode: %s\n' "$mode" >&2
    usage >&2
    exit 2
    ;;
esac
