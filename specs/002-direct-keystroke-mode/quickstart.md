# Quickstart — Direct Keystroke Streaming Mode

How to run the verification checks for the Direct Keystroke Streaming Mode feature
(spec at `specs/002-direct-keystroke-mode/spec.md`, task plan at
`specs/002-direct-keystroke-mode/tasks.md`). Closes T047.

## Prerequisites

- Xcode 17 with iOS 26.2 simulator runtime installed.
- iPhone 17 Pro simulator and iPad Pro 13-inch (M5) simulator added to
  the simulator runtimes list (matches the constitution §VI iPhone-first
  verification matrix).
- `xcodegen` installed (`brew install xcodegen`).
- A clean working tree on `main` (or your feature branch).

## Run the unit tests (Core + App + fake-RFB integration)

```bash
# Whole feature in one shot (Core unit + App-model + fake-RFB byte trace).
swift test --filter "Direct"

# Targeted slices, useful when iterating on a single layer:
swift test --filter KeysymMappingTests
swift test --filter StickyModifierStateTests
swift test --filter KeystrokeEmitterTests
swift test --filter HardwareOnScreenIdentityTests
swift test --filter DirectKeystrokeModeTests          # App-model integration
swift test --filter KeyEventWireTests                 # against fake RFB server
```

All tests run without a simulator and without a network — they exercise the
`FakeRFBServer` / `FakeRFBClientMessageRecorder` capability fixtures.

## Capture and inspect screenshot evidence (US-1 / US-2 / US-5)

```bash
# Regenerate Xcode project after touching project.yml or app target sources.
xcodegen generate --spec project.yml

# US-1 — QWERTY page + special-keys page.
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/DirectKeystrokeKeyboardScreenshotsUITests \
  test

# US-2 — sticky modifier idle / armed / locked states.
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/DirectKeystrokeStickyModifierScreenshotsUITests \
  test

# US-5 — first-entry warning dialog + dock badge + HUD badge.
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/DirectKeystrokeBadgeAndWarningScreenshotsUITests \
  test

# Inspect the saved PNGs:
ls artifacts/screenshots/direct-keystroke/
```

The screenshot tests are frozen as evidence artifacts (PR-C / PR-D / PR-G).
Vision-judge each PNG against the spec — keyboard fills bottom area, no iOS
keyboard above it, modifier states visually distinct.

## Run the FR-001 / FR-009 / FR-010 XCUITest assertions (Phase 8)

These are pure-assertion tests — no screenshots, fast feedback for the
behavior contracts that block ship. Closes T042 / T043 / T044.

```bash
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/DirectKeystrokeFR001UITests \
  -only-testing:NaruRemoteUITests/DirectKeystrokeFR009UITests \
  -only-testing:NaruRemoteUITests/DirectKeystrokeFR010UITests \
  test
```

What each test asserts:

- `DirectKeystrokeFR001UITests` — toggling Direct shows the custom QWERTY
  keyboard and `app.keyboards.firstMatch.exists == false` (iOS system
  keyboard absent).
- `DirectKeystrokeFR009UITests` — first Direct entry of a fresh session
  shows the "Got it" warning dialog; second toggle in the same session does
  not.
- `DirectKeystrokeFR010UITests` — both dock and HUD `DirectModeBadge`
  instances appear when Direct is active and disappear when Compose is
  selected again.

## Trace KeyEvent wire bytes against the fake RFB server

```bash
# Terminal 1 — start the deterministic fake RFB server.
swift run FakeRFBServer \
  --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex \
  --port 5901

# Terminal 2 — run the wire-byte assertion harness.
swift test --filter KeyEventWireTests
```

`KeyEventWireTests` connects through the real socket, drives
`RFBNetworkClient.sendKeyEvent(...)`, and asserts the recorder's
`keyEvents` array matches the contract in
`specs/002-direct-keystroke-mode/contracts/keystroke-emitter.md`.

## Drive the simulator end-to-end (visual smoke test)

1. `xcodegen generate --spec project.yml`
2. Open `NaruRemote.xcodeproj` in Xcode, run on iPhone 17 Pro / iOS 26.2.
3. Add a profile pointing at a private VNC (Tailnet MagicDNS host or LAN IP).
4. Connect; in the dock tap the segmented control to switch to **Direct**.
5. The first time, dismiss the "Got it" warning dialog (FR-009).
6. Tap keys on the soft keyboard; the remote should receive single keystrokes.
7. Tap a modifier (Ctrl); the next letter is wrapped. Double-tap a modifier
   within 400 ms to lock; tap "Clr" to clear all sticky modifiers.
8. Plug a Magic Keyboard / Bluetooth keyboard; hardware keys flow through
   the same RFB key path (US-3 / FR-007).

## Manual physical-device test recipe (T045 / T046)

These two tasks **cannot** be auto-completed by the agent loop — they require
physical hardware and are tracked as residual risk per constitution §III.

- **T045** — connect to a real Mac VNC, enter Direct mode, run `vim`,
  navigate `h j k l`, save & quit `Esc :wq Return`. Record PASS/FAIL in
  `artifacts/manual-tests/direct-keystroke-vim.md` with a short screen
  recording.
- **T046** — same as T045 but with a Bluetooth Magic Keyboard attached.
  Cover Tab completion, `Ctrl-R` reverse search, `Ctrl-C` cancel.
  Record PASS/FAIL in `artifacts/manual-tests/direct-keystroke-hwkb.md`.

When T045 / T046 are recorded as PASS, mark the corresponding entries
in `tasks.md` complete and remove the residual-risk note from the
Phase 9 keyboard sub-track in `ROADMAP.md`.
