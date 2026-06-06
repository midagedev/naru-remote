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
  bounded-vnc-profile-sweep Short bounded VNC profile candidate sweep.
  physical-device-preflight Safe physical iPhone build/signing readiness labels.
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
  shift

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/naru-benchmark-output.XXXXXX")"
  RUN_WITH_WALL_TIMEOUT_EXPIRED=0
  if run_with_wall_timeout "$wall_timeout_seconds" "$@" >"$output_file" 2>/dev/null; then
    cat "$output_file"
    rm -f "$output_file"
    return
  fi

  if [[ "$RUN_WITH_WALL_TIMEOUT_EXPIRED" == "1" ]]; then
    printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-sweep","status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileSweep.timedOut"}\n'
  else
    printf '{"schemaVersion":1,"mode":"bounded-vnc-profile-sweep","status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileSweep.failed"}\n'
  fi
  rm -f "$output_file"
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
    development_team_status="missing"
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
    reject_extra_flag --stream-shape-profiles
    reject_extra_flag --stream-shape-transport
    reject_extra_flag --stream-shape-profile-iterations
    reject_extra_flag --timeout
    reject_extra_flag --idle-timeout
    cd "$repo_root"
    bounded_args=(
      --stream-shape-gate-preset sustained-v2-core
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
    json_benchmark_or_timeout_failure \
      45 \
      swift run --quiet VNCLiveBenchmark "${bounded_args[@]}"
    ;;
  physical-device-preflight)
    physical_preflight
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
