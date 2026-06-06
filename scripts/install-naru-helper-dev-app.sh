#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install-naru-helper-dev-app.sh [--set-launchctl-env] [--request-permission]

Builds NaruHelper and installs a local development app wrapper at:
  ${NARU_HELPER_DEV_APP_ROOT:-$HOME/Applications/NaruRemoteDev}/NaruHelperDev.app

Options:
  --set-launchctl-env   Set NARU_HELPER_EXECUTABLE for future GUI-launched shells.
  --request-permission  Run the helper's explicit Screen Recording request command.
  --help                Show this help.
USAGE
}

set_launchctl_env=0
request_permission=0

while (($#)); do
  case "$1" in
    --set-launchctl-env)
      set_launchctl_env=1
      ;;
    --request-permission)
      request_permission=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_root="${NARU_HELPER_DEV_APP_ROOT:-$HOME/Applications/NaruRemoteDev}"
app_path="$install_root/NaruHelperDev.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
helper_executable="$macos_path/NaruHelper"

cd "$repo_root"
swift build --product NaruHelper

rm -rf -- "$app_path"
mkdir -p -- "$macos_path"
cp -- ".build/debug/NaruHelper" "$helper_executable"
chmod 755 "$helper_executable"

cat > "$contents_path/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>NaruHelper</string>
  <key>CFBundleIdentifier</key>
  <string>com.naruremote.helper.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>NaruHelperDev</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSBackgroundOnly</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign - "$app_path" >/dev/null 2>&1

if ((set_launchctl_env)); then
  launchctl setenv NARU_HELPER_EXECUTABLE "$helper_executable"
fi

printf 'Installed NaruHelperDev.app\n'
printf 'Helper executable: %s\n' "$helper_executable"
if ((set_launchctl_env)); then
  printf 'Set launchctl env: NARU_HELPER_EXECUTABLE\n'
fi

"$helper_executable" --video-capability

if ((request_permission)); then
  "$helper_executable" --video-request-screen-recording-permission
fi
