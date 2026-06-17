# Data Model: Apple Remote Desktop Native Support Strategy

## AppleRemoteDesktopSupportTier

Fixed enum describing what Naru can safely offer.

- `vncCompatible`: available through public VNC-compatible Apple Screen Sharing.
- `helperBacked`: available only through a paired Naru Helper capability.
- `researchOnly`: documented Apple behavior that Naru cannot implement directly
  yet.
- `unsupported`: intentionally not supported.

Lifecycle: compile-time catalog value, exported only as fixed labels.

## AppleScreenSharingProfileHints

Derived profile guidance for Mac Remote Management / Screen Sharing.

Fields:

- `defaultPort`: fixed `5900`.
- `additionalDisplayPorts`: fixed `[5901, 5902]`.
- `requiresVNCViewerAllowed`: fixed boolean hint.
- `fullARDAdminAvailableThroughVNC`: fixed false.
- `publicInternetWarning`: fixed boolean derived from host classification.
- `helperUpgradeCandidate`: fixed boolean.

Lifecycle: derived from saved profile kind and host classification; no secrets.

## ARDClassHelperCapability

Fixed helper-advertised capability.

Initial values:

- `systemStatus`
- `messageUser`
- `fileStage`
- `wakeOrKeepAwake`
- `lockScreen`
- `powerAction`
- `shellCommand` (reserved; disabled until a separate approval spec)

Lifecycle: received from the helper capability response and retained only as
fixed safe labels.

## ARDClassActionRequest

User-confirmed helper-backed action request.

Fields:

- `actionKind`: fixed action label.
- `approvalState`: `notRequired`, `required`, `approved`, `denied`, or
  `expired`.
- `capabilityStatus`: `available`, `missing`, `permissionMissing`,
  `approvalRequired`, `researchOnly`, or `unsupported`.
- `resultState`: `notStarted`, `sent`, `completed`, `failed`, `timedOut`, or
  `cancelled`.
- `id`: random request identifier for diagnostics correlation.

Lifecycle: created when the user opens or confirms an action. The app may retain
redacted action status, never action payload text, file paths, command text,
screen content, hostnames, or endpoint values.

## MacSessionControl

Fixed VNC-compatible shortcut action for Apple-aware session navigation.

Initial values:

- `missionControl`: Control-Up Arrow
- `appWindows`: Control-Down Arrow
- `switchApplication`: Command-Tab
- `showDesktop`: F11 default shortcut
- `spaceLeft`: Control-Left Arrow
- `spaceRight`: Control-Right Arrow

Lifecycle: compile-time catalog value, rendered only for active sessions. It is
not persisted, does not require helper pairing, and does not retain user input.
Remote Macs with customized keyboard shortcuts may need a future per-profile
remapping model.
