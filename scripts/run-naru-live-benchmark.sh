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
  helper-screen-probe      Helper-video probe-only run with external ScreenCaptureKit.
  helper-readiness-sweep   Safe helper capability/preflight/synthetic/screen sweep.
  short-live-comparison    Short constrained-cellular VNC + synthetic helper-video run.
  glance-scale-sweep       Short 0.45/0.35/0.25 startup glance candidate sweep.
  glance-025-duration-probe Duration-only 0.25 startup glance local RGB565 probe.
  glance-025-profile-sweep Duration-only 0.25 startup glance app profile sweep.
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
  NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip

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
    jq -r '.result.devices[]? | .hardwareProperties.udid // .identifier // empty' "$output_file"
    status=$?
  fi
  rm -f "$output_file"
  return "$status"
}

physical_iphone_ids_from_xctrace() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  xcrun xctrace list devices 2>/dev/null |
    awk '/^== Devices ==/{in_devices=1; next} /^== Simulators ==/{in_devices=0} in_devices' |
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
  local signing_identity_status
  local development_team_status
  local build_check_status
  local provisioning_profile_status="unknown"
  local xcode_account_status="unknown"

  device_count="$(physical_iphone_device_count)"
  device_id="$(discover_physical_ios_device_id)"
  if [[ -n "${NARU_PHYSICAL_IOS_DEVICE_ID:-}" ]]; then
    device_selection_source="environment"
  elif [[ -n "$device_id" ]]; then
    device_selection_source="auto"
  else
    device_selection_source="none"
  fi

  if [[ -z "$device_id" ]]; then
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

  if [[ -z "$device_id" || "$device_status" == "multiple" || "$device_status" == "wrongDeviceType" ]]; then
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
  json_string_array "${issue_codes[@]}"
  printf ',\n'
  printf '  "setupActionLabels": '
  json_string_array "${setup_actions[@]}"
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
    ;;
  short-live-comparison)
    import_helper_env
    import_live_env
    cd "$repo_root"
    run_benchmark_with_extra \
      --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
      --visual-transport vnc,helper-video \
      --helper-video-probe external-helper-synthetic-encoded-tcp \
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
