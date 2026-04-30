# Data Model: Naru Remote MVP

## ConnectionProfile

Represents a saved private VNC target.

Fields:

- `id`: stable local identifier
- `displayName`: user-visible profile name
- `host`: MagicDNS name, private DNS name, or private IP
- `port`: VNC port, default `5900`
- `username`: optional metadata only
- `credentialRef`: optional secure-storage reference
- `favorite`: boolean
- `lastConnectedAt`: optional timestamp
- `lastDiagnosticSummary`: optional user-safe summary
- `allowsPiPWatch`: boolean, default `true`

Rules:

- Credentials are never stored in plain profile records.
- Public IPs are allowed only through advanced/manual entry copy.
- Deleting a profile must remove its credential reference.
- Sensitive profiles can set `allowsPiPWatch` to `false`; legacy decoded
  profiles default to allowing PiP Watch until the user changes the policy.

## FileConnectionProfilePersistence

Represents the app-local JSON persistence boundary for saved profiles.

Fields:

- `fileURL`: Application Support profile JSON location, or an injected test URL

Rules:

- Missing profile files load as an empty profile list.
- Saves create the parent directory and write profile JSON atomically.
- Credentials remain outside the profile file and must use secure storage when
  implemented.

## ConnectionDiagnosticRun

Represents one staged diagnostic attempt.

Fields:

- `id`
- `profileId`
- `startedAt`
- `finishedAt`
- `stages`: ordered list of `DiagnosticStageResult`
- `safeSummary`: text safe for export

Stage names:

- `dns`
- `tcp`
- `rfbHandshake`
- `authentication`
- `firstFrame`
- `clipboardText`

Rules:

- A failed stage stops later stages unless the stage is explicitly optional.
- Safe summaries must not include credentials, composed text, or screenshots.

## DiagnosticExport

Represents a user-shareable diagnostic summary.

Fields:

- `summary`: newline-delimited export text
- `detailLevel`: `summaryOnly` or `stageSummary`

Rules:

- `summaryOnly` includes stage, status, and title only.
- `stageSummary` uses a fixed stage catalog such as "Authentication stage."
  rather than caller-provided diagnostic detail.
- Raw `safeDetail`, raw `nextAction`, credentials, composed text, clipboard
  payloads, and framebuffer content are not accepted into the export API.

## RemoteSession

Represents an active or recently failed VNC session.

Fields:

- `id`
- `profileId`
- `state`: `connecting`, `authenticating`, `active`, `degraded`, `reconnecting`, `failed`, `closed`
- `viewportState`: zoom, pan, orientation, scale mode
- `hudState`: concise connection and send status
- `lastFrameAt`
- `lastError`

Rules:

- Session errors must be mapped to user-safe diagnostics.
- Closing a session must not delete the saved profile.
- PiP Watch availability requires both an allowed session state and at least one
  received remote frame.

## ComposeDraft

Represents local text not yet sent or recently sent.

Fields:

- `id`
- `sessionId`
- `text`
- `createdAt`
- `updatedAt`
- `sendState`: `idle`, `ready`, `sending`, `sent`, `failed`, `unknown`
- `lastInjectionPath`
- `lastFailureReason`
- `lastStatusMessage`

Rules:

- Failed or unknown send must keep `text` intact.
- Unknown send stores a status message, not a failure reason.
- Diagnostic export must not include `text`.
- Successful send may clear text only after a confirmation source proves the
  remote target accepted the text.

## TextInjectionAttempt

Represents a single attempt to send composed text to the remote.

Fields:

- `id`
- `draftId`
- `sessionId`
- `path`: `vncClipboardPaste`
- `startedAt`
- `finishedAt`
- `status`: `sent`, `failed`, `unknown`
- `remoteClipboardRestore`: `notAttempted`, `attempted`, `succeeded`, `failed`, `unsupported`
- `safeMessage`

Rules:

- Store status and safe message, not the text payload.
- Unknown status must be visible to the user and not reported as success.

## PiPWatchSession

Represents a watch-only Picture in Picture monitor for one remote session.

Fields:

- `id`
- `sessionId`
- `state`: `unavailable`, `stopped`, `preparing`, `watching`, `stale`, `failed`
- `startedAt`
- `lastFrame`
- `safeMessage`
- `inputPolicy`: always `watchOnly`
- `framePolicy`: adaptive frame interval and stale-frame threshold

Rules:

- PiP watch state must not imply interactive control.
- PiP watch state must keep pointer, keyboard, clipboard, and Compose & Send in
  the main app.
- PiP watch preparation must respect the selected profile's `allowsPiPWatch`
  policy and reject sessions without a received frame.
- PiP frame rendering must reject zero-width or zero-height frame snapshots.
- Failed or unsupported PiP must leave the main remote session usable.
- Diagnostic export must not include PiP frame contents.

## NaruRemoteAppModel

Represents the app-shell coordinator for the current MVP.

Fields:

- `profiles`
- `selectedProfileID`
- `session`
- `diagnosticRun`
- `composeDraft`
- `latestInjectionAttempt`
- `pipWatchSession`
- `connectorFactory`
- `latestFramebuffer`

Rules:

- Profile selection and creation update the current session/draft boundary.
- Connect starts a live no-auth first-frame RFB attempt against the selected
  profile through `RFBFirstFrameConnecting`.
- `RFBNetworkClient` can hold a no-auth session open and request repeated raw
  framebuffer updates on the active connection before those pixels are wired to
  the app renderer.
- `RFBNetworkClient` can also negotiate VNC password authentication when a
  password is supplied, while missing or rejected passwords fail without stale
  session/frame state.
- Optional VNC passwords are stored behind `credentialRef`; profile metadata
  does not include plaintext, and Connect resolves the stored password before
  authenticated streaming sessions.
- When the connector supports streaming, Connect reads the first raw framebuffer
  through `RFBFramePump` and stores it in `latestFramebuffer` for the session
  viewport preview.
- The app model keeps a frame task alive for streaming-capable connectors and
  updates `latestFramebuffer` as later frames arrive.
- The app model can start, refresh, and stop the core PiP Watch lifecycle once
  a selected frame-bearing session allows PiP; this does not claim the AVKit
  system PiP window is implemented.
- Selecting a different profile cancels the active frame task, clears
  `latestFramebuffer`, and starts a fresh session/draft boundary for the newly
  selected profile.
- Send uses the active connection's `RemoteClipboardTextClient` when available;
  when no active text client exists, the local draft is retained and marked with
  a recoverable failure.
- The MVP app model records user-safe staged diagnostic results for connection
  success or failure.
- It remains a single active controllable session coordinator; multi-session
  parking and split multi-view need a separate feature spec.

## RFBRawFramebuffer

Represents decoded raw framebuffer pixels.

Fields:

- `width`
- `height`
- `pixels`: row-major RGBA colors

Rules:

- Current decoder supports 32-bit true-color raw encoding only.
- Repeated network requests are supported at the client boundary and the app
  model now consumes repeated frames, but the viewport remains a sampled SwiftUI
  preview rather than a full-rate Metal/SwiftUI renderer.
- Incremental raw updates are applied onto the previous framebuffer instead of
  replacing the whole frame with only the dirty rectangle.
- Unsupported encodings, out-of-bounds rectangles, unsupported pixel formats,
  and incomplete payloads fail with typed errors.
- Raw framebuffer pixels are render data and must not be included in diagnostic
  exports or logs by default.

## RFBFramebufferUpdateResult

Represents one decoded framebuffer update after local composition.

Fields:

- `framebuffer`
- `dirtyRectangles`
- `changedPixelCount`
- `capturedAt`
- `changeActivity`: derived as `idle`, `moderate`, or `high`

Rules:

- Dirty rectangles describe the server update regions; renderers should use
  them for future Metal texture upload minimization.
- `changedPixelCount` is computed by comparing incoming pixels with the local
  previous framebuffer.
- `changeActivity` feeds PiP frame policy decisions so idle screens can reduce
  frame frequency while active screens can temporarily render faster.
- Raw pixels remain inside the framebuffer boundary and are not export/log data.

## RFBFramePump

Runs repeated framebuffer update requests against an `RFBFramebufferUpdating`
source.

Fields:

- `RFBFramePumpConfiguration.maxFrames`
- `RFBFramePumpConfiguration.requestTimeout`
- `RFBFramePumpConfiguration.frameInterval`
- `RFBFramePumpFrame.sequence`
- `RFBFramePumpFrame.framebuffer`
- `RFBFramePumpFrame.dirtyRectangles`
- `RFBFramePumpFrame.changedPixelCount`
- `RFBFramePumpFrame.changeActivity`
- `RFBFramePumpFrame.capturedAt`
- `RFBFramePumpFrame.isIncremental`

Rules:

- The first request is a full framebuffer update.
- Later requests are incremental updates.
- If the source exposes damage-tracking updates, the pump preserves dirty
  rectangles and change activity. Legacy sources are wrapped as full-frame
  updates.
- Pump execution can stop by frame limit, callback decision, cancellation, or a
  propagated source error.

## PiPFrameSnapshot

Represents metadata for the latest remote frame offered to PiP rendering.

Fields:

- `width`
- `height`
- `capturedAt`
- `changeActivity`: `idle`, `moderate`, `high`

Rules:

- Frame snapshot metadata may be logged, but raw pixels/screenshots are excluded
  from logs and diagnostic exports by default.
- Adaptive frame policy may lower frame frequency when change activity is idle.
- The current app model derives this activity from `RFBFramePumpFrame` metadata;
  the AVKit system PiP renderer is still a separate app-layer boundary.

## PiPWatchSampleBufferRenderer

Represents the app-layer bridge from Naru's composed framebuffer pipeline into
Apple's sample-buffer video path.

Fields:

- `displayLayer`: `AVSampleBufferDisplayLayer`
- `factory`: converts `RFBRawFramebuffer` into `CVPixelBuffer` and
  `CMSampleBuffer`
- `frameIndex`
- `timescale`

Rules:

- The pixel format is 32-bit BGRA because that is the efficient Core Video path
  used by the sample-buffer display layer.
- Zero-width or zero-height framebuffers are rejected before pixel-buffer
  allocation.
- Pixel-buffer base-address locking failures and display-layer failures are
  reported as safe renderer errors instead of being ignored.
- Presentation timestamps advance monotonically for each enqueued frame.
- The display layer uses aspect resizing so PiP does not distort the remote
  desktop.
- The iOS-only controller creates an `AVPictureInPictureController` content
  source from the sample-buffer display layer and conforms to
  `PiPWatchControlling`.
- `NaruRemoteAppModel` owns the injected PiP controller boundary, gates start by
  active frame and device support, enqueues the first framebuffer before
  requesting PiP start, forwards later stream frames while watching, and stops
  the controller when PiP/session state is cleared.
- Physical iPhone/iPad behavior and background-mode policy must be verified
  before full system PiP support is claimed.

## OnboardingGuide

Represents derived first-run setup state. It is not a raw event log and does not
retain user-entered payloads.

Fields:

- `steps`: ordered `OnboardingStep` list for private target, diagnostics,
  compose, and PiP Watch
- `firstActionableStep`: first step whose state is `next` or `blocked`
- `isComplete`: true only when all setup steps are complete

Rules:

- Guide content must be derived from safe state only.
- Guide content must not include composed text, credential values, raw clipboard
  payloads, or framebuffer pixels.
- Diagnostic failures may use `safeTitle`, but not raw `safeDetail`.
- Public endpoints are treated as advanced/manual setup.

## OnboardingStep

Represents one row in the first-run checklist.

Fields:

- `id`: `privateTarget`, `diagnostics`, `compose`, or `pipWatch`
- `state`: `complete`, `next`, `waiting`, or `blocked`
- `title`
- `detail`
- `actionTitle`

Rules:

- `detail` must be short and safe for UI display.
- `actionTitle` is a hint, not a permission grant.
