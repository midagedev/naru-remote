# Compose Input Scroll Safe-Area And Storm Fixture Fix - 2026-06-17

## Scope

This artifact records the simulator evidence for the Compose input freeze class
where Korean/CJK input stalled after the first syllable or made XCUITest wait
for app idle for hundreds of seconds. It covers input responsiveness only; it
does not claim VNC FPS, traffic, helper-video physical-device quality, or
thermal improvement.

## Before

The quickstart Compose UI run failed on the pre-connection profile-detail path:

```text
/tmp/naru-quickstart-compose-ui-20260616-215934.log
```

Key signal:

- `testComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput` failed.
- First syllable `입` was accepted.
- Second syllable `력` caused the test to wait for app idle from about `9.55s`
  to `380.23s`.
- The test failed after `381.352s` with the editor never satisfying
  `value CONTAINS "입력"`.

Follow-up full-suite runs also showed that XCUITest storm fixtures could make
otherwise passing Compose tests stretch into 400-1000 second idle waits. Those
long waits hid the product signal and made repeated verification too noisy.

## Root Cause

Two separate issues were found:

- The profile-detail content branch was a `ScrollView` with the input dock
  attached through `safeAreaInset`. In that branch, the UIKit `UITextView`
  used for Compose became part of the scrollable tree, which made Korean/CJK
  IME input vulnerable to scroll-view quiescence and keyboard idle waits.
- The simulator-only storm fixtures published model/helper/clipboard changes
  at 6-9ms cadence, and the trackpad cursor storm task did not have a static
  cancellation handle. This over-stressed XCUITest's app-idle detection rather
  than producing a clean product signal.

## Changes

- Wrapped the detail content branch in a stable `ZStack` so the bottom
  `safeAreaInset` input dock is attached outside the scrollable profile-detail
  content.
- Added a cancellable static handle for the trackpad cursor storm fixture.
- Paced model-publish, helper-video health, and incoming-clipboard chrome
  storm fixtures at 16ms cadence with bounded sample counts.
- Moved the delayed first-frame fixture to `1500ms` after Compose focus so the
  first frame still arrives during focused Korean/CJK composition, but not
  during the keyboard's initial appearance wait.

## After

Focused pre-connection regression:

```text
/tmp/naru-compose-profile-detail-zstack-fix-20260617-021937.log
```

Result:

- `testComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput` passed in
  `10.470s`.

Storm fixture spot checks:

```text
/tmp/naru-compose-trackpad-storm-paced-20260617-034415.log
/tmp/naru-compose-helper-health-storm-paced-20260617-034343.log
/tmp/naru-compose-connecting-delayed-frame-1500ms-20260617-040957.log
```

Results:

- Trackpad cursor storm passed in `12.341s`.
- Helper-video health storm passed in `16.075s`.
- Connecting delayed first-frame test passed in `17.029s`.

Final Compose UI suite:

```text
/tmp/naru-compose-ui-full-final-after-input-fixes-20260617-041048.log
```

Result:

```text
Executed 10 tests, with 0 failures (0 unexpected) in 128.695s.
```

Focused Swift checks:

```bash
swift test --filter 'RemoteInputDockRenderStateTests|RemoteInputDockSyncPolicyTests'
```

Result:

```text
Executed 74 tests, with 0 failures (0 unexpected).
```

## Decision

This is a clear Compose input responsiveness and verification-stability
improvement. It is eligible for a PR under the "only when there is a clear
measured improvement" rule, but it should be described as an input reliability
fix rather than a VNC FPS or network-traffic improvement.

## Privacy

The retained logs and this artifact contain test names, fixed fixture labels,
and aggregate timings only. They do not include hostnames beyond synthetic test
fixture names, credentials, target endpoints, frame pixels, byte counts,
physical device identifiers, raw clipboard contents, or user-entered text
beyond the fixed Korean test string used by the repository UI tests.
