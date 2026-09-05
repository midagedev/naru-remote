#!/usr/bin/env bash
#
# Naru Helper → signed, notarized GitHub Release, in one command.
#
#   scripts/release-naru-helper.sh --dry-run       # build → zip, then stop
#   scripts/release-naru-helper.sh                 # + notarize, staple, record
#   scripts/release-naru-helper.sh --publish       # + upload the GitHub Release
#
# What it does, in order: xcodegen the helper app project → xcodebuild
# archive (Developer ID Application, team XEF9KH7N43, hardened runtime) →
# -exportArchive (developer-id method) → codesign strict verify → ditto zip
# → notarytool submit --wait (fails unless the verdict is Accepted) →
# stapler staple → re-zip (the stapled app is what ships) → stapler
# validate → spctl --assess → write a record under artifacts/app-store/ →
# with --publish, gh release create (or gh release upload when the tag
# already exists), uploading Naru-Helper-<version>.zip.
#
# The app is "Naru Helper.app" (scheme NaruHelperApp), generated from
# NaruHelper/project.yml. The CLI in the root Package.swift is untouched
# by this script; it stays the benchmark/automation surface.
#
# Credentials (never in the repo, never echoed):
#
#   ~/.appstoreconnect/credentials.env          ASC_KEY_ID, ASC_ISSUER_ID (0600)
#   ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#
# Override the directory with ASC_CREDENTIALS_FILE / ASC_PRIVATE_KEY if they
# live somewhere else on another machine. notarytool takes the key id and
# issuer as arguments, so they are visible to anyone who can read this
# machine's process list while it runs — that is Apple's interface, not a
# choice — but nothing here writes them to a file, a log or the terminal,
# and the record at the end names neither.
#
# Runbook: specs/041-helper-menu-bar-app/quickstart.md

set -euo pipefail

TEAM_ID="XEF9KH7N43"
APP_NAME="Naru Helper.app"

version=""
dry_run=0
publish=0
allow_dirty=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --publish) publish=1 ;;
        --allow-dirty) allow_dirty=1 ;;
        --version)
            shift
            if [ $# -eq 0 ]; then
                echo "missing value for --version (want --version X.Y.Z)" >&2
                exit 64
            fi
            version="$1"
            ;;
        -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done

if [ -n "$version" ] && ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "--version must look like X.Y.Z (got: $version)" >&2
    exit 64
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
cd "$repo_root"

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# -------------------------------------------------- the app project (first)

# First check, on purpose: without NaruHelper/project.yml there is nothing
# to archive, and every tool below would fail less clearly than this.
[ -f "$repo_root/NaruHelper/project.yml" ] \
    || fail "NaruHelper/project.yml not found — run Round B (the helper app project) or see specs/041-helper-menu-bar-app/quickstart.md"

# ---------------------------------------------------------------- work tree

if [ "$allow_dirty" -eq 0 ] && [ "$dry_run" -eq 0 ] \
    && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    fail "work tree is dirty — a release should be reproducible from a commit (--allow-dirty to override, or --dry-run)"
fi

command -v xcodegen >/dev/null || fail "xcodegen is required to generate the helper app project"

# ------------------------------------------------------------------ version

read_setting() { # read_setting <key> <file>
    sed -nE "s/^ +$1: +([^ ]+) *$/\1/p" "$2" | head -1
}

if [ -z "$version" ]; then
    version="$(read_setting MARKETING_VERSION NaruHelper/project.yml)"
    [ -n "$version" ] || version="$(read_setting MARKETING_VERSION project.yml)"
    [ -n "$version" ] || fail "could not read MARKETING_VERSION from NaruHelper/project.yml (or project.yml) — pass --version X.Y.Z"
fi
build_number="$(read_setting CURRENT_PROJECT_VERSION NaruHelper/project.yml)"
[ -n "$build_number" ] || build_number="$(read_setting CURRENT_PROJECT_VERSION project.yml)"
[ -n "$build_number" ] || fail "could not read CURRENT_PROJECT_VERSION from NaruHelper/project.yml (or project.yml)"

log "Releasing Naru Helper $version (build $build_number)"

# ------------------------------------------------------------------ archive

log "Regenerating the helper app project"
xcodegen generate --spec NaruHelper/project.yml >/dev/null

stamp="$(date +%Y%m%d-%H%M%S)"
work_dir="${TMPDIR:-/tmp/}naru-helper-release-$stamp"
archive_path="$work_dir/NaruHelper.xcarchive"
export_dir="$work_dir/export"
app_bundle="$export_dir/$APP_NAME"
zip_path="$work_dir/Naru-Helper-$version.zip"
mkdir -p "$work_dir"

log "Archiving Release for macOS (Developer ID Application; this takes a few minutes)"
xcodebuild archive \
    -project NaruHelper/NaruHelper.xcodeproj \
    -scheme NaruHelperApp \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    ENABLE_HARDENED_RUNTIME=YES \
    > "$work_dir/archive.log" 2>&1 \
    || { tail -40 "$work_dir/archive.log"; fail "archive failed — full log at $work_dir/archive.log"; }

# ------------------------------------------------------------------- export

log "Exporting the Developer ID build"
xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$repo_root/scripts/ExportOptions-helper.plist" \
    -exportPath "$export_dir" \
    > "$work_dir/export.log" 2>&1 \
    || { tail -40 "$work_dir/export.log"; fail "export failed — full log at $work_dir/export.log"; }

[ -d "$app_bundle" ] || fail "export produced no '$APP_NAME' in $export_dir — see $work_dir/export.log"

# ------------------------------------------------------------------- verify

log "codesign --verify --deep --strict on the exported app"
codesign --verify --deep --strict --verbose=2 "$app_bundle" \
    > "$work_dir/codesign.log" 2>&1 \
    || { tail -20 "$work_dir/codesign.log"; fail "codesign strict verify failed — full log at $work_dir/codesign.log"; }
codesign_team="$(sed -n 's/^TeamIdentifier=//p' "$work_dir/codesign.log" | head -1)"

# ---------------------------------------------------------------------- zip

log "Zipping $APP_NAME for notarization"
ditto -c -k --keepParent "$app_bundle" "$zip_path"

# ------------------------------------------------------------------ dry run

if [ "$dry_run" -eq 1 ]; then
    log "--dry-run: stopping after the zip. Steps not run:"
    printf '  6. xcrun notarytool submit <zip> --key <p8> --key-id <ASC_KEY_ID> --issuer <ASC_ISSUER_ID> --wait --output-format json\n'
    printf '  7. xcrun stapler staple the app, re-zip (the stapled app is what ships), xcrun stapler validate\n'
    printf '  8. spctl --assess -vv --type execute the app\n'
    printf '  9. write artifacts/app-store/<YYYYMMDD>-helper-%s/release.md\n' "$version"
    printf ' 10. --publish only: gh release create v%s-helper (this run: --publish=%s)\n' "$version" "$publish"
    log "Artifacts in $work_dir"
    exit 0
fi

# -------------------------------------------------------------- credentials

credentials_file="${ASC_CREDENTIALS_FILE:-$HOME/.appstoreconnect/credentials.env}"
[ -f "$credentials_file" ] || fail "no credentials at $credentials_file (see specs/041-helper-menu-bar-app/quickstart.md)"

# shellcheck disable=SC1090
set +u
. "$credentials_file"
set -u

[ -n "${ASC_KEY_ID:-}" ] || fail "ASC_KEY_ID missing from $credentials_file"
[ -n "${ASC_ISSUER_ID:-}" ] || fail "ASC_ISSUER_ID missing from $credentials_file"

private_key="${ASC_PRIVATE_KEY:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
[ -f "$private_key" ] || fail "no API private key at the expected path (AuthKey_<key id>.p8)"

# ------------------------------------------------------------- notarization

log "Submitting the zip for notarization (waits for Apple's verdict)"
notary_json="$work_dir/notarization.json"
# The key id and issuer are argv because that is notarytool's interface;
# the JSON output carries only id, status and message — never the key id.
xcrun notarytool submit "$zip_path" \
    --key "$private_key" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait \
    --output-format json \
    > "$notary_json" 2> "$work_dir/notarytool.err" \
    || { tail -20 "$work_dir/notarytool.err" >&2; fail "notarytool submit failed — stderr log at $work_dir/notarytool.err"; }

notary_field() { # notary_field <key>, from the JSON written above
    python3 -c 'import json,sys; d=json.load(open(sys.argv[2])); print(d.get(sys.argv[1], ""))' "$1" "$notary_json"
}
notary_status="$(notary_field status)" || fail "could not parse notarytool output at $notary_json"
notary_id="$(notary_field id)" || fail "could not parse notarytool output at $notary_json"

if [ "$notary_status" != "Accepted" ]; then
    notary_message="$(notary_field message)" || notary_message=""
    [ -z "$notary_message" ] || printf '  notarytool: %s\n' "$notary_message" >&2
    fail "notarization status was '$notary_status' (expected Accepted) — full output at $notary_json"
fi
notary_id="${notary_id:-unknown}"
log "Notarization Accepted (id $notary_id)"

# ---------------------------------------------------- staple, re-zip, gates

log "Stapling the notarization ticket to the app"
xcrun stapler staple "$app_bundle" \
    > "$work_dir/staple.log" 2>&1 \
    || { tail -20 "$work_dir/staple.log"; fail "stapler staple failed — full log at $work_dir/staple.log"; }

log "Re-zipping (the stapled app is what ships)"
rm -f "$zip_path"
ditto -c -k --keepParent "$app_bundle" "$zip_path"

log "stapler validate"
xcrun stapler validate "$app_bundle" \
    > "$work_dir/staple-validate.log" 2>&1 \
    || { tail -20 "$work_dir/staple-validate.log"; fail "stapler validate failed — full log at $work_dir/staple-validate.log"; }

log "spctl --assess -vv --type execute"
spctl --assess -vv --type execute "$app_bundle" \
    > "$work_dir/spctl.log" 2>&1 \
    || { cat "$work_dir/spctl.log" >&2; fail "spctl rejected the app — full log at $work_dir/spctl.log"; }
spctl_source="$(sed -n 's/^source=//p' "$work_dir/spctl.log" | head -1)"

# ------------------------------------------------------------------- record

zip_sha256="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
record_dir="$repo_root/artifacts/app-store/$(date +%Y%m%d)-helper-$version"
mkdir -p "$record_dir"
{
    echo "# Naru Helper release — $version (build $build_number)"
    echo
    echo "- Released: $(date '+%Y-%m-%d %H:%M %Z')"
    echo "- Commit: $(git rev-parse --short HEAD)$([ -n "$(git status --porcelain --untracked-files=no)" ] && echo ' (dirty tree)')"
    echo "- Bundle: com.naruremote.helper, team ${codesign_team:-$TEAM_ID}"
    echo "- Zip: $(basename "$zip_path"), sha256 $zip_sha256"
    echo "- Notarization: Accepted (id $notary_id)"
    echo "- stapler validate: passed; codesign --verify --deep --strict: passed;"
    echo "  spctl --assess -vv --type execute: accepted (source=${spctl_source:-unknown})"
    echo
    echo "Produced by \`scripts/release-naru-helper.sh\`. Credentials were read from"
    echo "~/.appstoreconnect and are not recorded here; the key id appears only in"
    echo "the notarytool invocation and nowhere else."
} > "$record_dir/release.md"

log "Record: ${record_dir#$repo_root/}/release.md"

# ------------------------------------------------------------------ publish

if [ "$publish" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 \
        || fail "gh is required for --publish — install the GitHub CLI or re-run without --publish"
    gh auth status >/dev/null 2>&1 \
        || fail "gh is not authenticated — run 'gh auth login' before --publish"

    tag="v$version-helper"
    notes_file="$work_dir/release-notes.md"
    {
        echo "Naru Helper $version (build $build_number)"
        echo
        echo "Menu bar companion for Naru Remote: pairing by QR, native text"
        echo "insertion, and the hardware-codec video stream, in one process."
        echo
        echo "Signed with a Developer ID Application certificate, notarized and"
        echo "stapled; Gatekeeper accepts it with no override."
        echo
        echo "sha256: $zip_sha256"
    } > "$notes_file"

    if gh release view "$tag" >/dev/null 2>&1; then
        log "Release $tag already exists — uploading the asset"
        gh release upload "$tag" "$zip_path" \
            || fail "gh release upload failed (an asset with this name may already exist — delete it or bump the version)"
    else
        log "Creating GitHub release $tag"
        gh release create "$tag" \
            --title "Naru Helper $version" \
            --notes-file "$notes_file" \
            "$zip_path" \
            || fail "gh release create failed"
    fi
    log "Published: https://github.com/midagedev/naru-remote/releases/tag/$tag"
fi

log "Done. $zip_path"
