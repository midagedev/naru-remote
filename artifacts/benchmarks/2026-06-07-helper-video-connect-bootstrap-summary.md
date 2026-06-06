# Helper Video Connect Bootstrap Summary - 2026-06-07

## Scope

This slice connects the app-model helper-video bootstrap to the VNC connect
lifecycle. When an enabled private-network profile has helper-video pairing
metadata, the app waits until the first VNC framebuffer is active, loads the
helper-video pairing secret through the credential store off the MainActor, and
then starts the helper-video session runner.

## Result

- Accepted fake helper-video access units select `helperVideo` visual transport
  after VNC first frame while VNC pointer control remains active.
- Helper-video start failure keeps `vncFramebuffer`, the latest VNC framebuffer,
  the Compose draft, and the pointer input path active.
- Helper-video bootstrap failures record fixed helper-video state labels such as
  `transportFailed` / `unreachable`; the app does not persist helper endpoints,
  pairing secrets, payload bytes, frame content, dimensions, raw errors, or
  exact timings.

## Verification

```bash
swift test --filter NaruRemoteAppModelTests/testHelperVideoBootstrapStartsAfterVNCFirstFrameWithoutDroppingControl
swift test --filter NaruRemoteAppModelTests/testHelperVideoBootstrapFailureKeepsVNCFrameAndControlPathActive
```

## Residual Gate

True ScreenCaptureKit helper-video access-unit benchmarking still requires
Screen Recording permission for the stable development helper app bundle and a
physical iPhone verification pass.
