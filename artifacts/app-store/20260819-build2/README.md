# App Store screenshots — build 2 (2026-08-19)

The English (U.S.) sets prepared for Naru Remote 1.0.0 **build 2**. They
replace `20260712-211315/`, whose captures show the retired Direct mode and a
UI three specs old (011 / 012 / 013).

- `final-iphone/`: five screenshots for the 6.9" slot. 1320×2868, except
  `02-live-session.png` which is landscape 2868×1320.
- `final-ipad/`: four screenshots for the 13" slot, 2752×2064 landscape.

Directory order is the intended App Store order:

1. `01-hosts` — the host list: eight saved computers, all reachable, each with
   its own desktop preview.
2. `02-live-session` — the remote screen live, whole, with session chrome.
3. `03-compose-korean` — a Hangul draft in the Compose editor with the
   accessory strip above it, over a live session.
4. `04-function-row` — Type mode with the Fn row expanded (Home/End/PgUp/PgDn/
   Ins/F-keys) over the remote screen.
5. `05-diagnostics` — a diagnostics run that passed every stage through first
   frame. **iPhone only**: the sheet is a fixed-height form sheet on iPad and
   clips its last row (`NEXT_STEPS.md` P1).

All nine are the **dark** captures. Light captures exist as raw output but are
not uploaded: over a dark remote screen the dock's `.ultraThinMaterial`
resolves to a mid-gray while `.secondary` text stays dark, putting the status
line near 2:1 contrast (`NEXT_STEPS.md` P0 #6).

Captured from deterministic DEBUG-only XCUITest fixtures (`store-*` tokens in
`NaruRemote/iOSApp/UXAuditFixtures.swift`). Every file passed the capture
harness's dimension and **no-alpha** gates — App Store Connect rejects
screenshots carrying an alpha channel, and each rotated capture did until the
encode path was pinned to an alpha-free bitmap.

Procedure, simulator preparation (Korean keyboard, 9:41 status bar) and the
reasoning behind each slot's framing: `docs/store-screenshots.md`. Raw captures
(both appearances, both devices) land in `artifacts/screenshots/store/` and stay
local — one command regenerates them.
