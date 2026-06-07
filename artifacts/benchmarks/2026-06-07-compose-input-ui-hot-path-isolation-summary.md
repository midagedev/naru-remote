# Compose Input UI Hot Path Isolation Summary

Date: 2026-06-07

## Context

Physical iPhone feedback still reported that Compose mode could accept one
Korean syllable and then stop responding after a real VNC connection. Existing
iPhone simulator UI coverage already passed the visible regression shape:

- Compose editor accepts a second Korean syllable after the first input.
- Active-session compact Compose accepts the same sequence.
- The keyboard survives a stale "remote app confirmation unavailable" status
  clear after first input.
- Cursor and framebuffer stress fixtures do not collapse the focused keyboard.

That simulator pass narrows the suspect surface, but it does not prove the
physical iOS IME hot path is safe. The remaining risky design was immediate
SwiftUI binding/model mirroring from `UITextView` delegate callbacks while the
editor was first responder. Even if render-state isolation stops stream
telemetry from repainting the dock, first-syllable UIKit callbacks could still
mutate SwiftUI state under the active IME.

## Design Change

Focused Compose input now uses a single-writer model:

- While `UITextView` is first responder, UIKit owns the local draft text.
- Delegate callbacks update the commit controller snapshot, but do not mirror
  text into the SwiftUI binding while focused.
- Marked-text commit notifications do not push SwiftUI state while focused.
- SwiftUI reads the latest UIKit text only at explicit boundaries: Send, focus
  loss, or Direct-mode switch.
- The Send button stays available while focused because the final send payload
  is read from the commit controller instead of from mirrored SwiftUI text.

This keeps keyboard/IME editing independent from video frame churn, stream
stats, send-status clears, and unrelated app-model updates.

## Verification

Focused tests:

- `swift test --filter RemoteInputDockSyncPolicyTests`
- `swift test --filter RemoteInputDockRenderStateTests`

Simulator UI evidence:

- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests test`

All listed checks passed locally after the change.

## Privacy

This artifact records only fixed test names, design decisions, and aggregate
pass/fail evidence. It does not include host identity, credentials, command
text, draft text, marked text, IME state, keysyms, pointer coordinates, pixels,
dimensions, byte counts, raw timings, or physical device identifiers.
