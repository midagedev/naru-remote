# NAR-12 Active-Session Readability Evidence

Generated: 2026-06-13

## Scope

This bundle contains refreshed UX audit screenshots for active-session states
16, 17, and 18. The remote framebuffer is synthetic, non-secret content with a
desktop top bar, side panels, a terminal window, readable status text, and a
trackpad cursor fixture.

## Files

- `16-session-active-widescreen-iphone-dark.png`
- `16-session-active-widescreen-iphone-light.png`
- `17-session-active-keyboard-iphone-dark.png`
- `17-session-active-keyboard-iphone-light.png`
- `18-session-active-trackpad-cursor-iphone-dark.png`
- `18-session-active-trackpad-cursor-iphone-light.png`

## Verification

Targeted UI tests passed:

- `UXAuditScreenshotsUITests/testSessionActiveWidescreen_dark`
- `UXAuditScreenshotsUITests/testSessionActiveWidescreen_light`
- `UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_dark`
- `UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_light`

The first three passed on `iPhone 17 Pro (iOS 26.2)`. The light trackpad test
hit simulator launcher `NSMachErrorDomain -308` twice on that device before
app launch, then passed on `iPhone 17 (iOS 26.2)` and refreshed the
`18-session-active-trackpad-cursor-iphone-light.png` file.

Visual review confirmed:

- The active-session framebuffer is no longer a flat dark rectangle.
- Remote content includes readable non-secret text and visible window structure.
- The 16:9 framebuffer content is rendered without visible stretching.
- Keyboard-up captures keep useful remote content above the keyboard.
- Trackpad captures show the cursor over representative remote content.
