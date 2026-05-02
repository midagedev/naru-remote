# UX Audit Harness

How to drive a fresh UX audit:

1. Regenerate the iOS project so any new files in
   `NaruRemote/UITests/` land in the test target:

   ```bash
   xcodegen generate --spec project.yml
   ```

2. Run the iPhone audit (canonical phone-first device per
   constitution §VI):

   ```bash
   xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
     -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests \
     test
   ```

3. Run the iPad audit (portrait + landscape interleaved):

   ```bash
   xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
     -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
     -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testIPadStates \
     test
   ```

4. New screenshots land under
   `artifacts/screenshots/ux-audit/` (path is hard-coded in
   `UXAuditScreenshotsUITests.outputDirectory`).

5. Downsample to ~1500px before vision review so each PNG fits in a
   single Read tool image:

   ```bash
   mkdir -p /tmp/audit-thumb
   for f in artifacts/screenshots/ux-audit/*.png; do
     sips --resampleHeightWidthMax 1500 "$f" \
       --out "/tmp/audit-thumb/$(basename $f)"
   done
   ```

6. Open each thumb via the Read tool to vision-judge against
   `PUNCH_LIST.md` and `BRANDING.md`.

## Test-only fixture hooks

All hooks are no-ops when their env var is unset; production behavior
is unchanged.

- **`NARU_TEST_OVERRIDE_INTERFACE_STYLE`** (`Light` / `Dark`) — forces
  the root scene's color scheme via `.preferredColorScheme(...)`.
  See `NaruRemoteApplication.testOverrideColorScheme()`.  Closes
  punch-list #001 — the original `-AppleInterfaceStyle Dark` macOS
  user-default key was silently ignored on iOS.

- **`NARU_TEST_FIXTURE_SNAPSHOT`** — selects a synthetic
  `NaruRemoteAppSnapshot` from `UXAuditFixtures.swift`.  Valid
  tokens:
  - `diagnostics-populated` — four diagnostic stages including a
    `.running` row.
  - `onboarding-progress` — two `.complete` onboarding rows + a
    `.waiting` Compose locally row.
  - `onboarding-done` — every step `.complete`, active session, and
    `.watching` PiP session → renders `OnboardingReadyView`.
  - `diagnostic-error-dns` — failed-DNS stage from the catalog.
  - `incoming-clipboard` — an `.active` session with a pending
    incoming-clipboard review banner mounted via
    `recordIncomingClipboard(...)` post-init.
  - `sidebar-with-verdicts` — four profiles whose
    `lastDiagnosticVerdict` palette spans
    `.passed` / `.warning` / `.failed` / `.unknown`, so the leading
    status-dot color sweep is visible in the captured PNG.

- **`NARU_TEST_SUPPRESS_DIRECT_WARNING`** — bypasses the first-entry
  IME-off warning dialog so it doesn't block keyboard screenshots.

- **`NARU_TEST_PRELOCK_MODIFIERS`** — pre-locks specific sticky
  modifiers (e.g. `control`) so screenshot tests can capture the
  locked-state visual cue without racing the 400 ms double-tap window.

## Outputs

- `artifacts/screenshots/ux-audit/<state-tag>-<device>-<orientation>-<mode>.png`
- `PUNCH_LIST.md` (this directory) — the running record of findings.
- The XCUITest also attaches each PNG to the `.xcresult` bundle so
  attachments survive on CI even if the local working tree is
  blown away.
