# Interaction Smoothness Baseline Summary - 2026-06-06

This increment records the larger practical target for the iPhone interaction
work and tightens Compose Send around a real IME edge. It does not change VNC
stream defaults.

## Baseline Goal

Naru should feel closer to the iPhone Photos interaction model while still
being a VNC viewer:

- Direct pinch, zoomed pan, and deceleration keep visible movement on the
  UIKit/Core Animation hot path.
- SwiftUI/PiP viewport state is reconciled after the gesture settles instead
  of publishing on every touch sample.
- Zoomed trackpad cursor movement remains finger-paced while local follow-pan
  keeps the cursor in view.
- Compose Send preserves recently committed Korean/CJK/emoji IME text before
  any clipboard/helper dispatch.
- Diagnostics and benchmark artifacts stay fixed-catalog only.

## What Changed

- Kept the existing Metal gesture boundary intact instead of reintroducing
  display-link SwiftUI state publication during gestures.
- Added post-commit Compose stabilization: after the UIKit editor reports a
  marked-text commit, the next Send uses the bounded stabilization window even
  if `markedTextRange` is already clear.
- Documented the interaction gate as the next larger unit to compare against
  stream-profile experiments.

## Verification

- `swift test --filter RemoteInputDockSyncPolicyTests` passed.
- Full `swift test` passed: 861 tests, 10 skipped, 0 failures.
- iPhone 17 Pro / iOS 26.2 simulator build passed:
  `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests` passed. The retained result is only the pass/fail outcome; raw timing samples remain outside the artifact.
- Focused viewport regression gate passed:
  `PointerGestureResolverTests`, `ViewportGestureRedrawThrottleTests`,
  `SessionViewportViewGeometryTests`, and the app-model viewport interaction
  frame-pacing tests.

## Safety

This artifact stores only fixed design and verification labels. It does not
include draft text, marked text, IME state, host identity, credentials, port
value, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
counts, raw timings, or raw payloads.
