# Research: Naru Helper Menu Bar App

**Feature**: `specs/041-helper-menu-bar-app` · 2026-09-05

## R1 — How to build a macOS app bundle from this repository

Options considered:

1. **Assemble a bundle around a SwiftPM executable** (what
   `scripts/install-naru-helper-dev-app.sh` does today). Zero project
   churn, but no XCUITest, no archive/export pipeline, hand-written
   Info.plist and entitlements, and `swift build` cannot produce a
   `.app` that `xcodebuild -exportArchive` will notarize with Developer
   ID the standard way.
2. **Add a macOS target to the root `project.yml`.** The root project
   compiles `NaruRemoteCore` from sources as an iOS framework target; a
   macOS app depending on the *package* product of the same module would
   create two `NaruRemoteCore` modules in one project.
3. **Second XcodeGen spec at `NaruHelper/project.yml`** consuming the
   root package as a local dependency (`packages: NaruRemote: path: ..`).
   Clean separation; XcodeGen supports local packages; Xcode builds the
   SwiftPM targets for macOS exactly as `swift build` does.

**Decision**: option 3. Requires a `.library(name: "NaruHelperKit")`
product in `Package.swift` (today only `NaruRemoteCore`/`NaruRemoteApp`
libraries and executables are products).

## R2 — Menu bar surface

`MenuBarExtra` (SwiftUI, macOS 13+) with `.menuBarExtraStyle(.menu)` for
the menu and a separate `Window` scene (`openWindow`) for pairing. Package
floor is macOS 14, so no AppKit `NSStatusItem` fallback is needed.
`LSUIElement = true` removes the Dock icon. Sandbox off: Accessibility
(AXUIElement / CGEvent posting) and ScreenCaptureKit as used by the
helper do not run sandboxed.

## R3 — Login item

`SMAppService.mainApp.register()` / `.unregister()` /
`.status` (`.notRegistered`, `.enabled`, `.requiresApproval`,
`.notFound`) — macOS 13+. No launchd plist. `SMAppService.openSystemSettingsLoginItems()`
deep-links when approval is required. Wrap behind a protocol so the state
machine is testable with a fake.

## R4 — Permission panes

`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
and `…?Privacy_ScreenCapture`. Both verified working on macOS 14/15 in
public references; the app must still show the state itself because the
grant does not round-trip an event. Poll the existing probes
(`NaruHelperTextBridgeCapabilityProbe`, `NaruHelperVideoCaptureCapabilityProbe`)
every 2 s while a window is open. Screen Recording probes must not
trigger the system prompt on every poll — use the non-prompting check
(`CGPreflightScreenCaptureAccess`) for polling and the requesting call
only from the button.

## R5 — Port-in-use detection

`NWListener.stateUpdateHandler` reports `.failed(NWError.posix(.EADDRINUSE))`
after `start(queue:)`. Today `NaruHelperNetworkServer` and
`NaruHelperVideoStreamNetworkServer` do not expose the state handler; the
runtime adds an optional `onStateChange` on both servers (additive API,
CLI unaffected).

## R6 — Revoke semantics (defect found while specifying)

`NaruHelperPairingStateStore.currentSecret()` returns the cached token
when the file cannot be read — for **any** reason. Deleting the file
therefore does not revoke. Fix: `FileManager.fileExists` (or `ENOENT`
from the read error) ⇒ clear cache and return `nil`; other errors ⇒ cache.
Handlers must treat provider `nil` as "refuse", so the provider type
changes from `() -> String` to `() -> String?`. FAIL-first: write the
absent-file test first against the current code and record the failure.

## R7 — QR image

`CIQRCodeGenerator` (already used by the terminal renderer) → `CIContext`
→ `CGImage`; scale with `CGInterpolationQuality.none` to ≥ 320 pt so
modules stay crisp. Correction level M as the CLI uses (parity of the
*string* is what matters; the image can differ).

## R8 — Notarization

`xcrun notarytool submit <zip> --key <p8> --key-id <id> --issuer <iss> --wait`
then `xcrun stapler staple "<app>"`. Same ASC API key as
`scripts/testflight-upload.sh` (`~/.appstoreconnect/credentials.env` +
`private_keys/AuthKey_<id>.p8`). Export with `method: developer-id`,
`signingStyle: manual`, `teamID: XEF9KH7N43`. Developer ID Application
certificate present on the founder's Mac (verified 2026-09-05).

## R9 — Distribution

GitHub Releases on `midagedev/naru-remote` (public since spec 039). Asset:
`Naru-Helper-<version>.zip` (ditto-created, stapled app inside). The
iPhone pointer is `https://github.com/midagedev/naru-remote/releases/latest`.
