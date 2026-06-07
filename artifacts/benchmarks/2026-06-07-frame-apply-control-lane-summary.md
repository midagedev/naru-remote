# Frame Apply Control-Lane Summary - 2026-06-07

## Scope

Physical iPhone feedback still points to interaction freezing when real VNC
frames begin flowing. The preceding frame-application cadence change prevents
repeated content frame application from monopolizing the MainActor, but a
single FIFO queue can still leave empty cursor/liveness updates behind a pending
content frame while the worker is in repeated-content mode.

This increment lets the frame-application worker ask the bounded queue to prefer
empty cursor/liveness work once at least one content frame has already been
applied. Initial content still follows normal order so the first visible frame
is not delayed.

No host names, credentials, ports, frame contents, framebuffer dimensions,
coordinates, pixels, byte counts, raw per-frame timings, raw TCP/RFB errors,
draft text, marked text, keysyms, pointer coordinates, screenshots, device
identifiers, or command text are recorded here.

## Change

- Extend `SessionStreamFrameApplicationQueue.next` with a
  `preferControlUpdates` option.
- When that option is true, the queue returns the first retained empty
  liveness/cursor update before pending content work.
- Enable that option only after the frame-application worker has already
  applied a content frame, preserving first-frame startup behavior.

## Interpretation

This is a control-lane priority guard, not a new VNC performance claim. It
keeps lightweight connection/cursor state from being blocked by content-frame
pacing while preserving the existing content coalescing behavior.

The remaining physical gate is still a real iPhone session check: connect to
the Mac, start receiving VNC frames, and verify that gestures, trackpad cursor
movement, server cursor shape/liveness, and Compose input continue responding
during the startup burst.

## Verification

Completed local verification:

```bash
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests/testSessionStreamFrameApplicationQueue
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests
swift test
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
```

Results so far:

- Queue-focused tests passed: 3 tests, 0 failures.
- `NaruRemoteAppModelTests` passed: 141 tests, 0 failures.
- Full `swift test` passed: 1149 tests, 13 skipped, 0 failures.
- The iPhone 17 Pro simulator app build succeeded for iOS 26.2.
