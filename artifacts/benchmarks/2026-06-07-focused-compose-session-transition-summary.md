# Focused Compose Session Transition Summary - 2026-06-07

## Purpose

Reproduce and close a narrower Korean/CJK Compose freeze path observed during
real VNC connection startup: the editor accepts the first character, then a
first remote frame activates the session and changes the dock around the active
UIKit input surface.

## Reproduction

The failing regression is:

```bash
swift test --filter RemoteInputDockRenderStateTests/testFocusedInputDockRenderStateDefersLiveSessionLayoutTransition
```

Before the fix, the focused render-state comparison failed because the first
frame/session activation changed:

- `layoutStyle`: `standard` -> `compactAccessory`
- `showsComposeQuickKeys`: `false` -> `true`

The Compose draft text was unchanged. That makes the failure a local UI
identity problem, not a remote text injection or VNC decode problem.

## Change

While Compose owns focus and Direct mode is inactive,
`RemoteInputDockRenderState` now treats live-session dock layout, quick-key
availability, model-mirrored draft text, helper-status text, and sticky
modifier state as advisory. The `UITextView` bridge stays stable until focus
leaves.

Send-result status is kept outside the hot editor identity while focused, so
user-facing confirmation/failure chrome can remain visible without remounting
the `UITextView`. The follow-up artifact
`2026-06-07-focused-compose-and-helper-readiness-order-summary.md` records the
post-send status-clear fix that keeps this sibling line mounted through the
keyboard transaction. When the editor is not focused, the same
`connecting -> active` transition still updates the dock to the compact live
layout and exposes quick keys.

## Verification

```bash
swift test --filter RemoteInputDockRenderStateTests
swift test --filter RemoteInputDockSyncPolicyTests
swift test
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests test
```

The targeted Swift suites pass after the change. The first suite proves the
focused session-transition reproduction and the unfocused live-layout behavior.
The second suite preserves the existing marked-text, binding-write, and Send
stabilization rules.

The full SwiftPM suite passes with 1188 tests executed and 14
benchmark/device-gated tests skipped. The iPhone 17 Pro simulator UI test
passes both Compose responsiveness paths, including the active-session compact
dock path that types a second Korean syllable after the first input.

## Interpretation

This is an input responsiveness fix. It does not claim that VNC now meets the
10fps visual target; the live readiness gate still measures VNC at about 2
content FPS with first-byte wait dominating. The architecture remains:
VNC for control/input/fallback, helper-video as the smooth visual candidate
after Screen Recording and physical iPhone gates pass.

## Privacy

This artifact records only fixed UI state labels and test names. It does not
include host identity, credentials, helper endpoints, framebuffer dimensions,
pixels, coordinates, byte counts, raw timings, keysyms, pointer coordinates,
live draft text, marked text, or IME state.
