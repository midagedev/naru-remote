# Quickstart: Apple Remote Desktop Native Support Strategy

## Readiness

```bash
! rg -n "\[NEEDS CLARIFICATION\]" \
  specs/008-apple-remote-desktop-native-support/spec.md \
  specs/008-apple-remote-desktop-native-support/plan.md \
  specs/008-apple-remote-desktop-native-support/research.md \
  specs/008-apple-remote-desktop-native-support/contracts
```

Expected: no matches.

## First Implementation Gate

After catalog code lands:

```bash
swift test --filter AppleRemoteDesktopSupportCatalogTests
```

Expected coverage:

- Apple Screen Sharing defaults to TCP `5900`.
- Additional display suggestions are fixed ports `5901` and `5902`.
- VNC-compatible support is distinct from full ARD administrator privileges.
- Helper-backed actions are hidden or disabled until helper capability and
  approval policy allow them.
- High Performance screen sharing is classified as `researchOnly` and routes to
  Naru Helper Video.

## Simulator UI Gate

After profile UI lands:

```bash
xcodebuild -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test
```

Expected: iPhone profile setup renders Apple-aware hints without exposing host
identity or promising unsupported ARD administrator features.

## Privacy Check

Diagnostic and catalog reports may include fixed capability IDs, fixed ports,
fixed setup labels, and coarse status. They must not include hostnames,
endpoints, credentials, message text, command text, file paths, usernames,
screenshots, pixels, coordinates, or exact timing series.
