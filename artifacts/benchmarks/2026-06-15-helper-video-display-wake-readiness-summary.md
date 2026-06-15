# Helper Video Display-Wake Readiness Summary

Date: 2026-06-15 KST

## Scope

This artifact records a Mac-side helper-video readiness improvement only. It
does not claim product Green, live iPhone FPS improvement, network traffic
improvement, or a successful physical-device end-to-end pass.

## Before

Live helper-video readiness could be blocked while Screen Recording permission
was granted and the helper process was otherwise runnable. In the observed
Screen Sharing environment, ScreenCaptureKit did not expose a usable display
capture source until the display was explicitly woken. The live gate therefore
reported a helper screen-capture blocker instead of reaching the physical
iPhone handoff.

Safe observed labels:

- `overallGateState=blockedByHelperScreenCapture`
- `helper-video-capture-non-displayable-frames`
- `helper-video-app-bootstrap-capture-non-displayable-frames`

## Change

The helper now holds a short display-wake assertion for both finite and
streaming ScreenCaptureKit capture startup. If the first shareable-content
query has no display capture source, the helper waits briefly and queries
ScreenCaptureKit once more before falling back to the existing window-source
selection.

## After

After refreshing the helper app and rerunning the live helper-video gate on the
same machine, the Mac-side helper path reached the physical iPhone handoff
instead of the ScreenCaptureKit blocker.

Safe observed labels:

- `overallGateState=blockedByPhysicalIPhoneGate`
- external synthetic helper-video probe: `pass`
- sustained synthetic helper-video probe: `pass`
- ScreenCaptureKit helper-video probe: `pass`
- sustained ScreenCaptureKit helper-video probe: `pass`
- app bootstrap ScreenCaptureKit path: `passed`

## PR Gate Interpretation

This is enough for a scoped PR only because it removes a concrete helper-video
readiness blocker in the live gate. It is not enough to merge a product-default
visual-path change. The remaining required evidence is a physical iPhone
helper-video gate and a sustained input/viewport session on device.

## Privacy

This artifact intentionally omits hostnames, endpoints, credentials, app or
window names, display dimensions, screenshots, raw frame payloads, byte counts,
exact timing series, raw OS errors, and physical device identifiers.
