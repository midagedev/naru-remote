# Helper Video Stale Callback Guard Summary - 2026-06-07

## Context

Live simulator/device feedback showed that the session could enter an
interaction-freeze-like state immediately after connection. The current VNC
benchmark evidence still shows a slow visual path, but this pass focused on a
separate lifecycle risk: late helper-video callbacks were still allowed to
mutate app visual/profile state after the referenced session had already failed
or closed.

## Reproduction

Added a regression test that initializes a session with the same session/profile
identity as the callback, but with an inactive lifecycle state.

Pre-fix behavior reproduced the bug:

- `updateHelperVideoStreamHealth(... state: .stalled ..., sessionID: closedSession.id)`
  changed helper-video health from `idle` to `fallbackToVNC`.
- `setHelperVideoProfileState(... availability: .failed ..., sessionID: closedSession.id)`
  changed profile availability from `available` to `failed`.
- The visual fallback failure reason changed to
  `streamHealthRequiresVNCFallback`.

This demonstrated that session identity alone was not a strong enough callback
guard. A late stream callback could still rewrite UI-visible state even though
the session lifecycle no longer accepted media updates.

## Design Change

`RemoteSessionState` now owns the lifecycle decision through
`acceptsSessionScopedMediaCallbacks`. Session-scoped helper-video callbacks are
accepted only when the current session ID matches and the current session state
can still own media callbacks:

- `connecting`
- `authenticating`
- `active`
- `degraded`
- `reconnecting`

Callbacks with a session ID are ignored for:

- `failed`
- `closed`

Helper-video visual selection and late stream callbacks now share that same
state-machine definition. Profile-only user actions remain allowed because the
lifecycle gate is applied only when a session-scoped asynchronous callback
includes `sessionID`.

## Verification

Passing focused checks after the fix:

```text
swift test --filter NaruRemoteAppModelTests/testHelperVideoCallbacksAfterInactiveSessionDoNotMutateVisualOrProfileState
swift test --filter NaruRemoteAppModelTests/testStaleHelperVideoCallbacksDoNotOverrideCurrentVisualState
swift test --filter RemoteSessionTests/testMediaCallbacksAreAcceptedOnlyWhileSessionLifecycleIsActive
```

The new regression test covers both `failed` and `closed` session states and
asserts that late callbacks do not mutate:

- `visualTransportMode`
- `helperVideoStreamHealth`
- `helperVideoStreamDescriptor`
- `helperVideoVisualSelectionFailureReason`
- helper-video profile availability/failure code
