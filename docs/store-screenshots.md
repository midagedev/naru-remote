# App Store screenshots

How the five App Store Connect screenshots are produced. They are captured by
the same UI-test harness as the UX audit captures, from dedicated fixtures, so
re-shooting after a UI change is one command per device rather than a manual
session with a simulator.

Store PNGs land in `artifacts/screenshots/store/`, beside — never inside — the
audit tree.

## The five slots

| Slot | File stem | State | The claim |
|---|---|---|---|
| 1 | `store-01-hosts` | Host list, eight saved machines, all reachable with desktop previews | Every computer on your tailnet, one tap away |
| 2 | `store-02-session` | Live session, no dock open, session chrome pinned | Your desktop, live on the phone |
| 3 | `store-03-compose-korean` | Compose editor holding a Hangul draft, accessory strip above it | Compose Korean locally, send it whole |
| 4 | `store-04-function-row` | Type mode with the Fn row expanded over a live session | Esc / Tab / ⌃C / F-keys, over the remote screen |
| 5 | `store-05-diagnostics` | Diagnostics sheet, every stage passed through first frame | When it does not connect, you learn which stage failed |

Each slot is captured in light and dark; the file stem carries the device
family and the mode, e.g. `store-03-compose-korean-iphone69-dark.png`.

**The shipped set is the dark one.** Light mode has a real legibility defect on
the dock over a live session (`.ultraThinMaterial` resolves to a mid-gray over a
dark remote screen while `.secondary` text stays dark, so the status line lands
near 2:1 contrast). Until that is fixed, light captures exist for comparison,
not for upload. See `NEXT_STEPS.md`.

## Running the capture

```bash
# One-time per capture simulator: install the Korean keyboard AFTER English
# (slot 3 shows 두벌식; English stays first so every other test's typeText
# keeps a Latin layout), then restart the simulator so the pref takes.
xcrun simctl spawn <udid> defaults write com.apple.Preferences AppleKeyboards \
  -array "en_US@sw=QWERTY;hw=Automatic" "ko_KR@sw=Korean - Kor 2 set;hw=Automatic" "emoji@sw=Emoji"
xcrun simctl shutdown <udid> && xcrun simctl boot <udid>

# Canonical status bar (9:41, full bars, charged) — do this before every run,
# it does not survive a simulator reboot.
xcrun simctl status_bar <udid> override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# iPhone 6.9" slot (1320×2868)
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testStoreHostList_dark \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testStoreLiveSession_dark \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testStoreKoreanCompose_dark \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testStoreFunctionRow_dark \
  -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testStoreDiagnosticsPassed_dark \
  test

# iPad 13" slot (2752×2064) — same five test names, different destination
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' ... test
```

`saveStoreScreen` refuses a capture App Store Connect would reject:

- **Pixel size** must be one of the accepted sizes for the family (6.9" iPhone:
  1320×2868 or 1290×2796; 13" iPad: 2064×2752 or 2048×2732, either
  orientation), so a wrong simulator fails in the run, not later in the upload
  UI.
- **No alpha channel.** Rotated captures go through
  `UIGraphicsImageRenderer`, and `format.opaque = true` is not enough on a P3
  device — the renderer picks an extended-range backing store and the PNG keeps
  premultiplied alpha, which App Store Connect refuses. Captures are re-encoded
  through a `noneSkipLast` bitmap; the gate proves it.

## The shipped iPad set is four shots, not five

Slots 1–4. Apple requires at least one iPad screenshot, not five. Slot 5's
diagnostics sheet renders as a fixed-height form sheet on iPad and clips its
last row ("First frame received") plus the Share button, so the capture exists
for reference but is not uploaded — see `NEXT_STEPS.md`.

## Why each slot is framed the way it is

- **Slot 2 is landscape on the phone**, unlike the other four. The hero
  viewport is aspect-**fill** by design — letterboxing a 16:9 desktop into a
  portrait phone leaves it unreadably small — so a portrait capture crops the
  remote screen mid-word. Apple accepts either orientation per slot.
- **The iPad gets a 4:3 remote screen** (`NARU_TEST_FIXTURE_DESKTOP=tablet`). A
  13" iPad in landscape is 4:3; aspect-fill crops a quarter off the width of a
  16:9 frame there. The phone keeps 16:9, which is what a real desktop usually
  is.
- **The store desktop's layout is fractional and keeps content inside
  y ∈ [40, 320] of 360.** Whatever the frame is taller than the screen gets
  cropped (~9% top and bottom on a 6.9" phone in landscape), and only the empty
  menu-bar band may leave the frame — never a glyph.
- **The iPad slots 3 and 4 put the soft keyboard away.** On a 13" iPad it eats
  half the screen and squeezes the remote screen into a cropped band, and it is
  the wrong story: the iPad scenario is an external keyboard and mouse, with the
  dock keeping its strip and the remote screen keeping the screen.
- **Slot 3's Hangul comes from the fixture, not from `typeText`.** Simulator IME
  typing is not reliable enough to gate a release capture on. The Korean
  *keyboard* is still real — a globe tap switches to it, idempotently, so the
  capture does not depend on test order.

## Fixtures

`NaruRemote/iOSApp/UXAuditFixtures.swift`, tokens `store-*`. They are separate
from the audit fixtures because the two jobs disagree: an audit frame wants
every failure badge visible at once, a store frame wants one healthy, legible
claim. Tightening a store shot must never weaken an audit shot's coverage.

The synthetic desktops are drawn by `FramebufferCanvas` in that file. Glyph
coverage is A–Z, 0–9 and space, and 13 characters is the widest line the
terminal window fits — anything else renders as `?`.

## Copy constraints

Store text and captions must not claim behaviour the build does not have:

- **No "bring the remote clipboard back to your iPhone".** Incoming clipboard
  review ships inert on the streaming path (see `SUBMISSION_READINESS.md` #7).
- **No Tailscale affiliation** and no public-internet-first framing
  (constitution principle II).
