# Quickstart: Naru Remote MVP Verification

The current implementation includes a Swift Package foundation with
`NaruRemoteCore` and `NaruRemoteApp`, plus an installable iOS/iPadOS app target
generated from `project.yml` with XcodeGen. Physical device IME checks remain
pending.

## Prerequisites

- Swift 6-compatible toolchain
- SwiftUI package shell target for `NaruRemoteApp`
- XcodeGen 2.44-compatible project generation
- Installable Xcode app bundle for `NaruRemote`
- iOS/iPadOS simulator support
- At least one physical iPhone or iPad for IME/manual verification
- Fake RFB server or fixture harness
- Optional real VNC servers for macOS, Linux, and Windows compatibility checks

## Current Automated Commands

Run from the repository root:

```bash
# Build the Swift package
swift build

# Run core unit tests
swift test

# Generate the Xcode project
xcodegen generate --spec project.yml

# Build the iOS/iPadOS app shell
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build

# Run the iPad simulator UI launch test
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' test
```

Run the deterministic fake RFB server manually when an integration target needs
a TCP fixture:

```bash
swift run FakeRFBServer --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex --port 5901
```

Current automated evidence:

- 2026-04-29: `swift build` passed.
- 2026-04-30: `swift test` passed with 99 XCTest tests for profile storage,
  concurrent profile saves, diagnostics, diagnostic export privacy/redaction,
  compose drafts, text injection unknown-state handling, session state, RFB
  handshake/first-frame header decoding, RFB client message encoding for UTF-8
  `ClientCutText` and paste key events, networked fake RFB serving, production
  `RFBNetworkClient` fake-server integration, failed-reconnect frame clearing,
  short-transcript rejection, app shell presentation state, app-model
  profile/add/connect/send coordination, file-backed launch profile persistence,
  32-bit raw framebuffer RGBA decoding, repeated raw framebuffer update
  requests over one active no-auth connection, cancellable frame pump behavior,
  long-lived app frame streaming with profile-change cancellation, first raw
  framebuffer storage in the app model, VNC password challenge-response,
  authenticated fake-server session coverage, credentialRef-only profile
  password storage, Keychain-backed app credential lookup boundary, incremental
  raw framebuffer compositing with dirty-region/change metadata, PiP Watch Mode
  state/profile policy, app-level PiP Watch lifecycle, sample-buffer renderer
  conversion, app-model system PiP controller wiring, and first-run onboarding
  safety.
- 2026-04-29: `xcodebuild ... build` passed for the generated
  `NaruRemote.xcodeproj` iPad simulator app target.
- 2026-04-29: `xcodebuild ... test` passed with XCUITest launch and
  keyboard-adjacent compose checks on iPad Pro 13-inch (M5), iOS 26.2
  simulator.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed after adding PiP Watch Mode profile opt-out, frame-gated availability,
  and disabled no-op app-shell affordance coverage.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed after adding the first-run onboarding shell and launch UI assertions.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed after wiring model-driven Add Profile/Checks/Connect, interactive
  no-auth first-frame handshake, outgoing RFB clipboard/paste messages, Send
  button model wiring, and safe-catalog diagnostic export behavior.
- 2026-04-30: `swift test` passed after removing the hard-coded launch profile,
  adding app-local file-backed profile persistence, and adding the raw
  framebuffer decoder.
- 2026-04-30: `swift test` passed after adding the no-auth session path and
  repeated raw framebuffer update request/receive/decode coverage against the
  fake RFB server.
- 2026-04-30: `swift test` passed after adding `RFBFramePump`, app-model first
  framebuffer storage, and the sampled SwiftUI framebuffer preview path.
- 2026-04-30: `swift test` passed after wiring the streaming frame task into the
  app model, verifying later frames replace earlier framebuffers, and ensuring
  profile changes cancel stale streams and clear framebuffer state.
- 2026-04-30: `swift test` passed after adding VNC password authentication
  response generation, authenticated fake-server sessions, missing-password
  reporting, and rejected-password handling.
- 2026-04-30: `swift test` passed after adding credential storage boundaries,
  Profile Editor password capture, credentialRef-only profile persistence, and
  app-model credential lookup for authenticated streaming connections.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after wiring the Keychain-backed credential store into
  the iOS app model and adding the Profile Editor password field.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after adding the VNC password authentication
  primitive and CommonCrypto-backed core implementation.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after wiring the long-lived app frame streaming task
  and stale-stream cancellation.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after removing the hard-coded launch profile,
  verifying empty first-run launch state, Add Profile presentation, and the
  keyboard-adjacent compose dock.
- 2026-04-30: `xcodebuild ... test` passed with 3 XCUITests after adding the
  repeated raw framebuffer update network primitive.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after adding `RFBFramePump`, first framebuffer app
  storage, and sampled SwiftUI framebuffer preview support.
- 2026-04-30: `swift test` passed with 91 XCTest tests after adding app-level
  PiP Watch start/stop/staleness lifecycle, incremental raw framebuffer
  compositing over previous frames, dirty-rectangle metadata, changed pixel
  counts, change activity, and fake-server partial incremental update coverage.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after syncing the optimized frame pipeline and
  app-level PiP Watch lifecycle.
- 2026-04-30: `swift test` passed with 95 XCTest tests after adding
  `RFBRawFramebuffer` to `CVPixelBuffer` / `CMSampleBuffer` conversion,
  `AVSampleBufferDisplayLayer` enqueue coverage, and iOS-only
  `AVPictureInPictureController` content-source wrapper compilation.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after the sample-buffer PiP renderer boundary.
- 2026-04-30: `swift test` passed with 99 XCTest tests after injecting the
  `AVPictureInPictureController` wrapper into `NaruRemoteAppModel`, adding
  unsupported-device/render-failure handling, and verifying active PiP receives
  later streaming framebuffers.
- 2026-04-30: `xcodegen generate --spec project.yml` and `xcodebuild ... test`
  passed with 3 XCUITests after system PiP controller wiring compiled in the
  iOS simulator app target.
- 2026-04-29: Standalone simulator install/launch was smoke-tested with
  `simctl` after directly embedding both `NaruRemoteApp.framework` and
  `NaruRemoteCore.framework` in the generated app target.
- 2026-04-29: iPad simulator screenshots were captured for the app shell and
  Korean/English/emoji local compose state:
  `artifacts/screenshots/naru-ipad-app-shell-fixed.png` and
  `artifacts/screenshots/naru-ipad-compose-korean.png`.
- 2026-04-29: The Remote Input Dock was moved to a bottom safe-area inset and
  an XCUITest verifies the compose editor stays directly above the iPad
  keyboard while composing.
- 2026-04-30: PiP Watch Mode state modeling, watch-only input policy, stale-frame
  handling, profile-level opt-out, frame-gated availability, unrenderable frame
  rejection, and app-shell presentation status are covered by XCTest.
- 2026-04-30: First-run onboarding checklist state, failed diagnostic safe
  display, PiP opt-out display, and composed-text non-disclosure are covered by
  XCTest.

## Pending Commands

No automated command is blocked on missing targets. Physical device checks are
still pending:

```bash
# Manual physical iPhone/iPad IME check
[manual device checklist below]
```

## Manual Device Checks

### Profile And Diagnostics

1. Connect the device to a tailnet or private network.
2. Create a profile using a MagicDNS hostname or private host address.
3. Run diagnostics.
4. Confirm each stage is understandable and user-safe.

### Compose & Send

1. Focus a text field in the remote session.
2. Compose this string locally:

   ```text
   한글과 English 😊를 같이 입력합니다
   ```

3. Tap Send.
4. Confirm the local draft is retained on failure or the remote receives the
   same Unicode string on success.
5. Confirm diagnostic exports do not include the composed text.
6. Confirm the compose field sits directly above the iPad keyboard while editing.

Status: simulator local compose smoke check passed; physical iPhone/iPad
verification remains pending.

### Viewport

1. Open a session on iPad.
2. Rotate the device.
3. Try split view or Stage Manager where available.
4. Confirm the remote viewport and Remote Input Dock remain usable.

Status: simulator launch and screenshot verification passed; physical iPad
viewport checks pending.

### PiP Watch

1. Open a frame-bearing session on a physical iPhone/iPad.
2. Start PiP Watch from the session surface.
3. Confirm the PiP window starts, shows the remote frame stream, and remains
   watch-only.
4. Switch to another app, then tap PiP to return to Naru Remote.
5. Confirm stopping PiP leaves the main session usable.

Status: sample-buffer renderer, iOS PiP content-source wrapper, and app-model
controller wiring compile and unit tests pass; physical iPhone/iPad PiP behavior
remains pending.

## Completion Criteria

- Unit tests pass.
- Fake RFB fixture verifies the no-auth first-frame path over TCP.
- Production `RFBClientBoundary` integration is demonstrated against the fake
  server.
- iOS/iPadOS app bundle builds and a simulator launch UI test passes.
- One physical iPhone/iPad manual IME check is recorded.
- Known limitations are documented in `research.md` or implementation notes.
