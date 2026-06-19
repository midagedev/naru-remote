# Screen-First UX Targets — 2026-06-18

## Scope

This note records the current UX target for the Naru Remote iPhone/iPad shell:
make the remote screen the dominant surface, keep in-session controls compact,
and verify every critical screen in light and dark mode before claiming a
quality step.

## Research Inputs

- Apple HIG Layout: layouts should adapt across device context changes while
  remaining consistent.
  <https://developer.apple.com/design/human-interface-guidelines/layout>
- Apple HIG Dark Mode: use system-adaptive backgrounds and verify contrast in
  both appearances.
  <https://developer.apple.com/design/human-interface-guidelines/dark-mode>
- Apple HIG iPadOS: iPad layouts must survive orientation, multitasking, Dark
  Mode, and Dynamic Type changes.
  <https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados>
- Chrome Remote Desktop iPhone/iPad help: remote access defaults to virtual
  trackpad control, hides browser chrome for fullscreen, and exposes session
  controls from an edge menu.
  <https://support.google.com/chrome/answer/1649523?co=GENIE.Platform%3DiOS&hl=en>
- Jump Desktop iPad input methods: persistent controls include keyboard,
  disconnect, show/hide menubar, zoom out, and gesture settings; gestures cover
  pinch zoom, scroll, quick keyboard show/hide, and desktop panning.
  <https://support.jumpdesktop.com/hc/en-us/articles/216423623-iPad-Input-methods>
- Splashtop iOS controls: advanced controls live in a menu bar opened by a
  gesture or corner control, and include trackpad mode, display switching,
  arrow keys, keyboard, and hiding the control bar.
  <https://support-splashtoponprem.splashtop.com/hc/en-us/articles/214200526-Using-the-Controls-Menu-Bar-for-iOS-clients>

## Target Principles

1. The active session viewport gets first claim on vertical space. Keyboard,
   Mac controls, quick keys, diagnostics, and mode controls must compress into
   accessory surfaces instead of becoming permanent panels.
2. The default in-session state should read as "remote desktop first". Controls
   are present, discoverable, and one tap away, but idle chrome is collapsed or
   icon-only.
3. Trackpad and zoom/pan interactions must remain local and immediate. Remote
   frame cadence must not be required for finger-follow movement.
4. Light and dark screenshots are both required for the connection grid,
   diagnostics, active session, keyboard-up Compose, Direct input, and trackpad
   cursor states.
5. iPhone is the gate. iPad landscape/portrait proves graceful scaling, not a
   substitute for phone usability.

## Current Baseline Findings

- The connection grid already starts as the primary saved-profile entry point,
  with a large card and visible reachability status.
- The active-session viewport uses the full hero layout, but the screenshot
  fixture was a flat color, making visual inspection too weak.
- The live Compose accessory still consumes too much vertical space when extra
  Mac/quick controls render as permanent strips.
- The iPad landscape Compose screenshot shows the Send area close to the
  keyboard boundary; this must stay in the audit set until regenerated from the
  current branch.

## Acceptance Bar For This UX Pass

- Active iPhone session, no keyboard: remote viewport occupies the screen above
  a single compact input row; Mac controls and quick keys are reachable from a
  compact menu, not a permanent second row.
- Active iPhone session, keyboard up: the visible remote viewport is larger
  than the dock accessory and remains readable.
- Trackpad cursor screenshot: cursor is visible over non-uniform remote content
  and the dock remains compact.
- iPad landscape Compose: Send remains visible and tappable above the software
  keyboard, with no text/button overlap.
- Screenshot output belongs to the current worktree, so before/after evidence
  can be attached to the same PR.

## Verification Commands

```sh
swift test --filter RemoteInputDockRenderStateTests

xcodebuild \
  -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testActiveSessionWidescreen_dark \
  test
```

