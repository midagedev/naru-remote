# Compose Model Echo Acknowledgment Summary

Date: 2026-06-07

## Scope

This increment addresses a local Compose synchronization policy issue. It does
not change VNC encoding selection, stream pacing, renderer upload behavior, or
diagnostic export schema.

## Change

- Accept an external model snapshot as acknowledged when it exactly matches the
  focused Compose editor's current text and no marked text is active.
- Keep marked-text protection intact for Korean/CJK composition windows.
- Keep deferring different non-empty external snapshots while a focused local
  draft is ahead of the model.

## Verification

- `swift test --filter RemoteInputDockSyncPolicyTests` passed.

New focused regressions:

- `RemoteInputDockSyncPolicyTests/testAppliesModelEchoMatchingFocusedLocalDraft`
- `RemoteInputDockSyncPolicyTests/testDefersModelEchoMatchingFocusedMarkedText`

## Interpretation

The previous policy could leave a focused committed local draft permanently
classified as ahead of the model. A later model clear, such as after a
successful send, could then be deferred even though the model had already echoed
the committed local value. Acknowledging matching model echoes fixes that state
transition without writing over UIKit's active marked-text composition.

## Follow-Up

Physical-device validation should type Korean text into Compose, send it,
verify the editor clears, and then continue composing in the same focused field.

## Privacy

This artifact contains no command text, draft text, marked text, IME state,
host identity, credentials, keysyms, pointer coordinates, dimensions, pixels,
byte counts, raw stdout/stderr, or raw network errors.
