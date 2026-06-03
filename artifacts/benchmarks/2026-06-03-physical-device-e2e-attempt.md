# Physical iPhone E2E Attempt

Date: 2026-06-03 KST

Device:

- Physical iPhone destination was detected by Xcode as an available iOS device.
- The device identifier, host, password, screenshots, and diagnostic payloads are
  not recorded here.

Configuration:

- Test: `NaruRemoteUITests/PhysicalDeviceConnectE2EUITests`
- Target profile host kind: `privateAddress`
- Target port: `5900`
- Password handling: shell prompt + environment variable; not included in the
  command line or artifact

Attempt 1:

- Command class: `xcodebuild ... -destination 'platform=iOS,id=<device-id>'`
- Result: build stopped before install because `NaruRemote`,
  `NaruRemoteUITests`, and `NaruRemoteBenchmarkTests` required a development
  team.

Attempt 2:

- Command class: same test with `DEVELOPMENT_TEAM=<local-team-id>` override.
- Result: signing progressed, but Xcode timed out waiting for the physical
  destination to become available.
- Safe Xcode detail: the device may need to be unlocked to recover from
  previously reported preparation errors.

Interpretation:

- The physical iPhone benchmark path is close: Xcode can see the device and the
  local machine has a valid Apple Development signing identity.
- The remaining blocker is device preparation/unlock state, not a failing app
  connection assertion.
- Next physical pass should unlock the device, keep it on the home screen, and
  rerun with the `DEVELOPMENT_TEAM` override before collecting sustained FPS,
  thermal, and VNC stream-shape evidence.
