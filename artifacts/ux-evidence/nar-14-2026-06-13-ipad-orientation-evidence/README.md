# NAR-14 iPad Screenshot Orientation Evidence

Date: 2026-06-13 KST

## Command

```bash
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testIPadStates \
  -resultBundlePath artifacts/ux-evidence/nar-14-2026-06-13-ipad-uxaudit.xcresult \
  test
```

## Result

- Verdict: passed
- Tests: 1 executed, 0 failures
- Device: iPad Pro 13-inch (M5), iOS Simulator 26.2
- Simulator UUID: 8F65B8FE-242C-4203-8BD8-5CC699588958
- Result bundle: `artifacts/ux-evidence/nar-14-2026-06-13-ipad-uxaudit.xcresult`

## Dimensions

- Portrait screenshots: 2064 x 2752 px
- Landscape screenshots: 2752 x 2064 px

These dimensions are iPad simulator captures from the iPad Pro 13-inch (M5)
run. They do not match the earlier iPhone-sized sample dimensions called out in
the issue.

## Screenshots

- `01-firstlaunch-ipad-portrait-light.png`
- `01-firstlaunch-ipad-portrait-dark.png`
- `01-firstlaunch-ipad-landscape-light.png`
- `01-firstlaunch-ipad-landscape-dark.png`
- `04-connection-grid-ipad-portrait-light.png`
- `04-connection-grid-ipad-portrait-dark.png`
- `04-connection-grid-ipad-landscape-light.png`
- `04-connection-grid-ipad-landscape-dark.png`
- `07-compose-text-ipad-portrait-light.png`
- `07-compose-text-ipad-portrait-dark.png`
- `07-compose-text-ipad-landscape-light.png`
- `07-compose-text-ipad-landscape-dark.png`
- `08-direct-qwerty-ipad-portrait-light.png`
- `08-direct-qwerty-ipad-portrait-dark.png`
- `08-direct-qwerty-ipad-landscape-light.png`
- `08-direct-qwerty-ipad-landscape-dark.png`

## Visual Orientation Check

Representative portrait and landscape captures were opened after the run:

- Connection grid portrait and landscape render upright.
- Compose dock landscape render is upright with the iPad software keyboard at
  the bottom edge.
- Direct keyboard landscape render is upright with the Remote Input Dock above
  the keyboard.

## Remaining Gap

This closes the simulator evidence gap for NAR-14. It does not claim physical
iPad orientation coverage.
