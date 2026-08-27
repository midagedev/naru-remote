## What this changes

<!-- One paragraph. What behaviour is different after this than before it? -->

## Spec

<!--
Behaviour changes need a `specs/<n>-<slug>/spec.md` — see CONTRIBUTING.md.
Link it here, or say why this doesn't change behaviour (typo, refactor, docs).
-->

## The gate

<!--
Which test fails without this change?  Please confirm you watched it fail:
revert the fix, run the test, see it red, restore.

    <test name>  —  FAIL-first confirmed / not applicable because …

If an existing test should have caught this and didn't, say why it couldn't.
-->

## Verification run

<!-- Paste the actual output, not a description of it. -->

```
swift test
xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
```

## Boundaries

- [ ] No credential reaches `ConnectionProfile`, the profile file, or a log
- [ ] No coordinates, byte counts, framebuffer dimensions, or user text in logs,
      diagnostic exports, or test assertions
- [ ] `NaruRemoteCore` still imports no SwiftUI and no UIKit
- [ ] `project.yml` regenerated if files were added or removed
