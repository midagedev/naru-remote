#!/usr/bin/env bash
#
# Naru Remote → TestFlight, in one command.
#
#   scripts/testflight-upload.sh --bump          # next build number, then ship
#   scripts/testflight-upload.sh                 # ship the build number in project.yml
#   scripts/testflight-upload.sh --dry-run       # archive + verify + validate, no upload
#
# What it does, in order: fast gates → build number → archive → **verify the
# archive against the submission contract** → export → `altool --validate-app`
# → `altool --upload-app` → poll App Store Connect until the build stops
# processing → write a record under artifacts/app-store/.
#
# The verification step is the point. Every item it checks is one that has
# actually gone wrong or would be invisible until Apple rejected it: a build
# number already taken, a debug fixture hook compiled into a release binary, a
# missing privacy manifest, an export-compliance key that would park the build
# in "Missing Compliance" instead of reaching testers.
#
# Credentials (never in the repo, never echoed):
#
#   ~/.appstoreconnect/credentials.env          ASC_KEY_ID, ASC_ISSUER_ID (0600)
#   ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#
# Override the directory with ASC_CREDENTIALS_FILE / ASC_PRIVATE_KEY if they
# live somewhere else on another machine.
#
# Runbook, including the account-owner web steps this script cannot do:
# docs/runbooks/testflight-release.md

set -euo pipefail

BUNDLE_ID="com.naruremote.app"
TEAM_ID="XEF9KH7N43"
SCHEME="NaruRemote"

bump_build=0
dry_run=0
allow_dirty=0
run_gates=1
status_only=0

while [ $# -gt 0 ]; do
    case "$1" in
        --bump) bump_build=1 ;;
        --dry-run) dry_run=1 ;;
        --allow-dirty) allow_dirty=1 ;;
        --no-gates) run_gates=0 ;;
        --status) status_only=1 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- credentials

credentials_file="${ASC_CREDENTIALS_FILE:-$HOME/.appstoreconnect/credentials.env}"
[ -f "$credentials_file" ] || fail "no credentials at $credentials_file (see docs/runbooks/testflight-release.md)"

# shellcheck disable=SC1090
set +u
. "$credentials_file"
set -u

[ -n "${ASC_KEY_ID:-}" ] || fail "ASC_KEY_ID missing from $credentials_file"
[ -n "${ASC_ISSUER_ID:-}" ] || fail "ASC_ISSUER_ID missing from $credentials_file"

private_key="${ASC_PRIVATE_KEY:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
[ -f "$private_key" ] || fail "no API private key at the expected path (AuthKey_<key id>.p8)"

# `altool` takes the key id and issuer as arguments, so they are visible to
# anyone who can read this machine's process list while it runs. That is
# Apple's interface, not a choice — but nothing here writes them to a file, a
# log or the terminal, and the record at the end names neither.
asc_api() { # asc_api <path-with-query>
    local token
    token="$(python3 "$repo_root/scripts/asc-jwt.py" "$private_key" "$ASC_KEY_ID" "$ASC_ISSUER_ID")"
    # `--globoff`: App Store Connect filters are `filter[app]=…`, and curl
    # would otherwise read those brackets as a glob range and refuse the URL.
    curl --silent --show-error --fail-with-body --globoff \
        -H "Authorization: Bearer $token" \
        "https://api.appstoreconnect.apple.com/v1/$1"
}

json_value() { # json_value <python-expression-on-`d`>
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"
}

# --------------------------------------------------------------- status only

read_setting() { # read_setting <key>
    sed -nE "s/^ +$1: +([^ ]+) *$/\1/p" project.yml | head -1
}

if [ "$status_only" -eq 1 ]; then
    version="$(read_setting MARKETING_VERSION)"
    build="$(read_setting CURRENT_PROJECT_VERSION)"
    app="$(asc_api "apps?filter[bundleId]=$BUNDLE_ID&fields[apps]=bundleId" | json_value 'd["data"][0]["id"]')"
    asc_api "builds?filter[app]=$app&filter[preReleaseVersion.version]=$version&limit=5&fields[builds]=version,processingState,uploadedDate,expired" \
        | python3 -c '
import json, sys
data = json.load(sys.stdin)["data"]
if not data:
    print("no builds uploaded for this version yet")
for b in data:
    a = b["attributes"]
    print(f'"'"'build {a["version"]}: {a["processingState"]}  uploaded {a.get("uploadedDate")}  expired={a.get("expired")}'"'"')
'
    echo "(project.yml currently points at build $build of $version)"
    exit 0
fi

# ----------------------------------------------------------------- work tree

if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    fail "work tree is dirty — a TestFlight build should be reproducible from a commit (--allow-dirty to override)"
fi

command -v xcodegen >/dev/null || fail "xcodegen is required to regenerate the app project"

if [ "$run_gates" -eq 1 ]; then
    log "Fast gates (swift test, skipping the live-Mac probes)"
    swift test --skip LiveMac > "$repo_root/.testflight-gates.log" 2>&1 \
        || { tail -40 "$repo_root/.testflight-gates.log"; fail "swift test failed — see .testflight-gates.log"; }
    grep -E "Executed [0-9]+ tests" "$repo_root/.testflight-gates.log" | tail -1
    rm -f "$repo_root/.testflight-gates.log"
fi

# -------------------------------------------------------------- build number

marketing_version="$(read_setting MARKETING_VERSION)"
build_number="$(read_setting CURRENT_PROJECT_VERSION)"
[ -n "$marketing_version" ] && [ -n "$build_number" ] || fail "could not read the version out of project.yml"

if [ "$bump_build" -eq 1 ]; then
    build_number=$((build_number + 1))
    log "Build number → $build_number"
    /usr/bin/sed -i '' -E "s/^( +CURRENT_PROJECT_VERSION: ).*$/\1$build_number/" project.yml
    [ "$(read_setting CURRENT_PROJECT_VERSION)" = "$build_number" ] || fail "the build-number edit did not take"
fi

log "Shipping $marketing_version (build $build_number)"

# App Store Connect refuses a duplicate build number for a version, and it
# does so *after* a full archive + upload. Ask first.
app_id="$(asc_api "apps?filter[bundleId]=$BUNDLE_ID&fields[apps]=bundleId" | json_value 'd["data"][0]["id"]')" \
    || fail "could not resolve the app record for $BUNDLE_ID"
existing="$(asc_api "builds?filter[app]=$app_id&filter[preReleaseVersion.version]=$marketing_version&filter[version]=$build_number&fields[builds]=version,processingState" \
    | json_value '",".join(b["attributes"]["processingState"] for b in d["data"])')"
if [ -n "$existing" ]; then
    fail "build $build_number of $marketing_version already exists upstream (state: $existing) — run with --bump"
fi

# ------------------------------------------------------------------- archive

log "Regenerating the app project"
xcodegen generate --spec project.yml >/dev/null

stamp="$(date +%Y%m%d-%H%M%S)"
work_dir="${TMPDIR:-/tmp/}naru-testflight-$stamp"
archive_path="$work_dir/NaruRemote.xcarchive"
export_dir="$work_dir/export"
mkdir -p "$work_dir"

log "Archiving Release for device (this takes a few minutes)"
xcodebuild archive \
    -project NaruRemote.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    > "$work_dir/archive.log" 2>&1 \
    || { tail -40 "$work_dir/archive.log"; fail "archive failed — full log at $work_dir/archive.log"; }

# ------------------------------------------------- verify the archive itself

app_bundle="$archive_path/Products/Applications/NaruRemote.app"
info_plist="$app_bundle/Info.plist"
[ -f "$info_plist" ] || fail "the archive has no app bundle where one is expected"

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist" 2>/dev/null || true; }

expect() { # expect <label> <actual> <wanted>
    if [ "$2" = "$3" ]; then
        printf '  ok   %-28s %s\n' "$1" "$2"
    else
        printf '  FAIL %-28s %s (expected %s)\n' "$1" "$2" "$3"
        verify_failed=1
    fi
}

verify_failed=0
log "Verifying the archive against the submission contract"
expect "CFBundleShortVersionString" "$(plist_get CFBundleShortVersionString)" "$marketing_version"
expect "CFBundleVersion" "$(plist_get CFBundleVersion)" "$build_number"
expect "CFBundleIdentifier" "$(plist_get CFBundleIdentifier)" "$BUNDLE_ID"
expect "MinimumOSVersion" "$(plist_get MinimumOSVersion)" "17.0"
# Without this key every upload lands in "Missing Compliance" and never
# reaches a tester until someone answers the export question by hand.
expect "NonExemptEncryption=false" "$(plist_get ITSAppUsesNonExemptEncryption)" "false"

if [ -f "$app_bundle/PrivacyInfo.xcprivacy" ]; then
    printf '  ok   %-28s present\n' "PrivacyInfo.xcprivacy"
else
    printf '  FAIL %-28s missing from the bundle\n' "PrivacyInfo.xcprivacy"
    verify_failed=1
fi

signing_team="$(security cms -D -i "$app_bundle/embedded.mobileprovision" 2>/dev/null \
    | /usr/bin/plutil -extract TeamIdentifier.0 raw - 2>/dev/null || true)"
expect "signing team" "${signing_team:-<none>}" "$TEAM_ID"

# The store fixtures and test hooks (`NARU_TEST_*`) are DEBUG-only. If one
# reaches a Release binary, a tester can drive the app into a fake session —
# so this is a gate, not a curiosity.
if strings "$app_bundle/NaruRemote" 2>/dev/null | grep -q "NARU_TEST_"; then
    printf '  FAIL %-28s NARU_TEST_* hooks are compiled into the Release binary\n' "test hooks"
    verify_failed=1
else
    printf '  ok   %-28s absent from the Release binary\n' "NARU_TEST_* hooks"
fi

[ "$verify_failed" -eq 0 ] || fail "the archive does not satisfy the submission contract (nothing was uploaded)"

# -------------------------------------------------------------------- export

log "Exporting a signed App Store build"
xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$repo_root/scripts/ExportOptions.plist" \
    -allowProvisioningUpdates \
    > "$work_dir/export.log" 2>&1 \
    || { tail -40 "$work_dir/export.log"; fail "export failed — full log at $work_dir/export.log"; }

ipa_path="$(/usr/bin/find "$export_dir" -name '*.ipa' -maxdepth 1 | head -1)"
[ -n "$ipa_path" ] || fail "export produced no .ipa"
log "Built $(basename "$ipa_path") ($(du -h "$ipa_path" | cut -f1))"

# ------------------------------------------------------ validate and upload

log "altool --validate-app"
xcrun altool --validate-app -f "$ipa_path" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
    > "$work_dir/validate.log" 2>&1 \
    || { tail -30 "$work_dir/validate.log"; fail "validation failed — full log at $work_dir/validate.log"; }
grep -q "VERIFY SUCCEEDED\|No errors validating" "$work_dir/validate.log" \
    || { tail -30 "$work_dir/validate.log"; fail "validation did not report success"; }
echo "  VERIFY SUCCEEDED"

if [ "$dry_run" -eq 1 ]; then
    log "--dry-run: stopping before upload. Artifacts in $work_dir"
    exit 0
fi

log "altool --upload-app"
xcrun altool --upload-app -f "$ipa_path" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
    > "$work_dir/upload.log" 2>&1 \
    || { tail -30 "$work_dir/upload.log"; fail "upload failed — full log at $work_dir/upload.log"; }
grep -q "UPLOAD SUCCEEDED\|No errors uploading" "$work_dir/upload.log" \
    || { tail -30 "$work_dir/upload.log"; fail "upload did not report success"; }
echo "  UPLOAD SUCCEEDED"

# ------------------------------------------------------------ wait for Apple

log "Waiting for Apple to finish processing build $build_number"
processing_state="UNKNOWN"
deadline=$(( $(date +%s) + 1800 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 30
    state="$(asc_api "builds?filter[app]=$app_id&filter[preReleaseVersion.version]=$marketing_version&filter[version]=$build_number&fields[builds]=version,processingState" \
        | json_value 'd["data"][0]["attributes"]["processingState"] if d["data"] else ""' 2>/dev/null || true)"
    [ -n "$state" ] || continue
    if [ "$state" != "$processing_state" ]; then
        processing_state="$state"
        echo "  processingState=$processing_state"
    fi
    case "$processing_state" in
        VALID|FAILED|INVALID) break ;;
    esac
done

# ------------------------------------------------------------------- record

record_dir="$repo_root/artifacts/app-store/$(date +%Y%m%d)-build$build_number"
mkdir -p "$record_dir"
{
    echo "# TestFlight upload — $marketing_version (build $build_number)"
    echo
    echo "- Uploaded: $(date '+%Y-%m-%d %H:%M %Z')"
    echo "- Commit: $(git rev-parse --short HEAD)$([ -n "$(git status --porcelain --untracked-files=no)" ] && echo ' (dirty tree)')"
    echo "- Bundle: $BUNDLE_ID, team $TEAM_ID"
    echo "- Archive contract: version/build, bundle id, MinimumOSVersion 17.0,"
    echo "  ITSAppUsesNonExemptEncryption=false, PrivacyInfo.xcprivacy present,"
    echo "  no NARU_TEST_* hooks in the Release binary — all verified pre-upload."
    echo "- altool: VERIFY SUCCEEDED, UPLOAD SUCCEEDED."
    echo "- App Store Connect processingState: $processing_state"
    echo
    echo "Produced by \`scripts/testflight-upload.sh\`. Credentials were read from"
    echo "~/.appstoreconnect and are not recorded here."
} > "$record_dir/upload.md"

log "Done. processingState=$processing_state"
log "Record: ${record_dir#$repo_root/}/upload.md"

case "$processing_state" in
    VALID)
        cat <<'EOF'

The build is processed and available in TestFlight. What this script cannot do
(account-owner web steps): assign it to the internal tester group, and answer
any first-time export-compliance prompt. See docs/runbooks/testflight-release.md.
EOF
        ;;
    FAILED|INVALID)
        fail "Apple rejected the build (processingState=$processing_state) — check App Store Connect for the reason"
        ;;
    *)
        echo
        echo "Still processing after 30 minutes; that is normal for a first upload."
        echo "Re-check with: scripts/testflight-upload.sh --status"
        ;;
esac
