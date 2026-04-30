# Contract: PiP Watch Mode

## Scope

PiP Watch Mode lets the user keep a remote desktop visible in Picture in Picture
while using another iPhone/iPad app. The PiP surface is watch-only.

## States

- `unavailable`: platform, app policy, profile policy, or session state does not
  allow PiP.
- `stopped`: PiP is available but not running.
- `preparing`: Naru is preparing the watch renderer.
- `watching`: PiP is showing current or recent remote frames.
- `stale`: no fresh frame has arrived within the configured stale threshold.
- `failed`: PiP could not start or continue; the main session remains usable.

## Availability Gates

PiP Watch Mode may become startable only when all gates pass:

- The selected profile allows PiP Watch.
- The session belongs to the selected profile.
- The session state is `active`, `degraded`, or `reconnecting`.
- The session has received at least one remote frame.

The current app shell may start the core watch lifecycle once those gates pass.
Starting the core lifecycle updates Naru state and can feed frames into the
sample-buffer renderer boundary. The current iOS app injects a
`PiPWatchControlling` wrapper around `AVPictureInPictureController` so the app
model can prepare, start, stop, and enqueue initial/subsequent frames. The
system PiP start action still requires additional release gates:

- The iOS app layer has created an `AVPictureInPictureController` content source
  from the sample-buffer display layer.
- The active device reports PiP support before the PiP Watch button becomes a
  start action.
- Physical iPhone/iPad verification proves PiP can start, stay visible, return
  to the session, and stop without enabling remote input from the PiP surface.
- Background-mode and App Review policy are documented before full support is
  claimed.

If physical-device behavior is not verified yet, the app must not claim system
PiP support is complete.

## Input Policy

PiP Watch Mode must not accept or emit:

- pointer events
- keyboard events
- clipboard changes
- Compose & Send actions
- file/image drops
- agent approvals

Tapping the PiP window may return the user to Naru Remote. The resumed main app
session owns all remote interaction.

## Frame Policy

The PiP renderer receives frame metadata and, in the iOS app layer, video frames
derived from the same locally composed VNC framebuffer used by the main
viewport. The core policy selects a target frame interval based on remote change
activity carried through `RFBFramePump`:

- idle changes: low frequency
- moderate changes: medium frequency
- high changes: higher frequency

Dirty rectangles and changed-pixel counts should be preserved so the main
renderer can minimize Metal texture uploads and the PiP renderer can downsample
or throttle without running a second decode pipeline.

The current renderer boundary converts remote framebuffers into 32-bit BGRA
`CVPixelBuffer`, wraps those buffers as `CMSampleBuffer`, and enqueues them on an
`AVSampleBufferDisplayLayer`. The exact system PiP behavior must be verified
with AVKit on iPhone/iPad before full PiP support is claimed.

Frame snapshots with zero width or zero height are not renderable and must move
the watch state to a recoverable failure.

## Privacy

- PiP must be user-initiated.
- PiP frames and screenshots are not stored in logs or diagnostic exports by
  default.
- Sensitive profiles must be able to disable PiP.
- Diagnostic export may include PiP state and frame dimensions, but not pixels.
