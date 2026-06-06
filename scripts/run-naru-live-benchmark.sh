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
  request-pipeline-sweep   Short VNC-only constrained-cellular depth 1/2/3 sweep.
  screen-recording-setup   Request helper Screen Recording and open Settings.
  helper-capability        Run the selected helper's safe --video-capability.
  request-screen-recording Run the selected helper's explicit permission request.

Launchctl variables used when present:
  NARU_HELPER_EXECUTABLE
  NARU_LIVE_MAC_HOST
  NARU_LIVE_MAC_PORT
  NARU_LIVE_MAC_PASSWORD
  NARU_LIVE_STIMULUS_COMMAND
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
