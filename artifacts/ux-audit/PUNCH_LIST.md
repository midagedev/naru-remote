# Naru Remote — UX & Design Audit (2026-05-02)

Original capture context (from `chore/ux-audit-screenshots`): iPhone 17
Pro / iOS 26.2 + iPad Pro 13" / iOS 26.2 simulator.

This file is the running record of the UX polish workstream — original
findings + their resolution + anything new the re-audit surfaced.  See
`README.md` (next to this file) for how to drive the harness.

## Resolution status (post-Chunk 8)

PRs in the workstream: **#36 → #43**.

### P0 — Critical

- ✅ **#001** Dark mode is not actually applied — every "dark"
  screenshot is identical to its "light" pair — **PR #36** added the
  `NARU_TEST_OVERRIDE_INTERFACE_STYLE` hook + adaptive `NaruColors`
  surfaces.  Every `*-dark.png` in the new capture is visibly distinct
  from its light pair.
- ✅ **#002** iPad landscape screenshots are saved 90° rotated — **PR
  #36** added `orientedPngData(from:)` so the captured PNG is
  byte-rotated into the active orientation.  Status bar reads upright
  on every iPad capture in `artifacts/screenshots/ux-audit/`.
- ✅ **#003** First Run sheet bleeds onto the iPad detail column —
  **PR #36** combined with the rotation fix means the "duplicate
  column" effect was the rotation artifact.  iPad portrait + landscape
  re-captures (this PR) confirm the layout is single-column-of-stacks
  with First Run banner + viewport + dock pinned via
  `safeAreaInset(.bottom)`.  See
  `01-firstlaunch-ipad-landscape-light.png`.
- ✅ **#004** Hero title "Naru Remote" clipped on the left edge — **PR
  #38** added `.padding(.horizontal, 16)` to the outer
  `SessionViewportView` `VStack`.  Hero title + subtitle render
  without clipping.
- ✅ **#005** Three-pill action row stacks Label icon-over-text —
  **PR #38** moved the action row below the title row on compact
  width, gave each pill the full row width, and used `.iconOnly` for
  Checks + PiP Watch on compact while keeping Connect labeled.  Status
  Label uses `.fixedSize(horizontal: true, vertical: false)`.  See
  `04-profile-selected-iphone-light.png`.
- ✅ **#006** Public-IP profile has only an icon to convey "advanced"
  — **PR #40** added a coral "Public address — advanced" caption row
  and the warning triangle leading the public-test row.  See
  `14-sidebar-multiple-iphone-light.png`.
- ✅ **#007** "Diagnostics populated" and "Onboarding progress"
  showed no diagnostics / no progress — **PR #37** wired the audit
  harness to launch with `NARU_TEST_FIXTURE_SNAPSHOT` tokens
  (`diagnostics-populated`, `onboarding-progress`).  States #05 and
  #06 now exercise distinct cell mixes.  See
  `05-diagnostics-populated-iphone-light.png` (four diagnostic rows
  including a `.running` authentication row) and
  `06-onboarding-progress-iphone-light.png` (two `.complete` rows +
  Compose locally `.waiting`).
- ✅ **#008** No persistent IME-incompatibility cue on Direct mode —
  **PR #42** repainted `DirectModeBadge` to read "Direct — IME off"
  on a coral pill with a warning glyph; the badge stays put as long
  as Direct is active.  See `08-direct-qwerty-iphone-light.png`,
  `09-direct-special-iphone-light.png`, `11-modifier-locked-iphone-light.png`.
- ✅ **#009** Korean keyboard pushes First Run, clipping bottom row —
  **PR #39** binds onboarding to a `@FocusState` in the compose
  editor; when the editor takes focus the checklist collapses to a
  1-line "First Run · 0 of 4 done — Private target" summary banner.
  See `07-compose-text-iphone-light.png`.

### P1 — Important

- ✅ **#101** "Add Profile" appears twice on first launch — **PR #39**
  removed the duplicate; the toolbar now exposes a `+` plus button on
  the sidebar only and the OnboardingGuideView surfaces a single
  "Add Profile" CTA inside the active First Run row when no profile
  exists.
- ✅ **#102** Profile editor — no validation, no Test affordance —
  **PR #41** disabled Save until name + host are non-empty, added a
  "Port" label with `1…65535` validation, and added a "Test" button
  that runs DNS + TCP + RFB-handshake and renders a one-line
  reachability outcome.
- ✅ **#103** PiP-after-first-frame chip shown with no session — **PR
  #38** gates the chip on `framebuffer != nil`.  See
  `01-firstlaunch-iphone-light.png` — no phantom chip.
- ✅ **#104** Three-pill action row + status run off the right edge —
  closed by **PR #38** alongside #005.
- ✅ **#105** Onboarding mixes Tailnet concepts without Tailscale-
  affiliation guardrail — **PR #39** added "Naru does not configure
  Tailscale — set up your tailnet first." subtitle to First Run +
  reworded the active row to "Use your Tailscale MagicDNS name (e.g.
  studio.tailnet.ts.net) or any private host you can reach."
- ✅ **#106** Onboarding active row not visually distinct — **PR #39**
  bumped the active row to `.semibold` Ink + accent-tinted background
  + "Next" CTA pill.  Inactive rows use muted Ink.  See
  `01-firstlaunch-iphone-light.png` (Private target row).
- ✅ **#107** Direct mode badge duplicated in HUD + dock — **PR #42**
  removed the HUD instance.  The dock badge is the durable
  disclosure since the dock is always pinned via
  `safeAreaInset(edge: .bottom)`.
- ✅ **#108** Selection cue in profile list is a tiny green check —
  **PR #40** applied an accent-tinted row pill background to the
  selected row + retained the green active-session check as a
  separate signal.  See `14-sidebar-multiple-iphone-light.png`.
- ✅ **#109** No connection-status indicator per profile in the
  sidebar — **PR #40** added a leading colored verdict dot per
  profile (green = `.passed`, amber = `.warning`, red = `.failed`,
  gray = `.unknown`).  Re-audit fixture (Chunk 8) wires
  `sidebar-with-verdicts` token into the harness so the colored
  palette is captured in `14-sidebar-multiple-with-verdicts-*.png`.
- ✅ **#110** Modifier-locked "LOCK" Latin text — **PR #42** replaced
  the inline "LOCK" with a thin filled bottom rule + Signal Blue key
  fill + VoiceOver-friendly accessibility label.  See
  `11-modifier-locked-iphone-light.png`.

### P2 — Nice-to-have

- ✅ **#201** Empty viewport hero reads like marketing copy — **PR
  #38** swaps to "Pick a computer" / "Choose a profile from the
  sidebar to begin." when `selectedProfile == nil`.
- ✅ **#202** First Run checklist does not collapse as steps complete
  — **PR #39** ships the active-row-only collapsed presentation when
  steps land, plus the keyboard-collapse summary banner.  Final
  state lands `OnboardingReadyView`.  See
  `16-onboarding-done-iphone-light.png`.
- ✅ **#203** Hairline divider above the dock is invisible against
  the canvas — **PR #42** uses `NaruColors.hairline` (1pt) for the
  dock top border.
- ✅ **#204** Send paperplane has no breathing room — **PR #42**
  bumped compose-row spacing to 16 with extra trailing inset.
- ✅ **#205** Direct QWERTY page indistinguishable from iOS keyboard
  — **PR #42** changed the page-toggle label from `123` to `⇄`,
  added a "Direct space" label + accent-tinted spacebar, and pulled
  the keyboard background to `NaruColors.dock`.
- ✅ **#206** iPad layout breathing room unverifiable — closed by
  this PR (Chunk 8).  iPad portrait + landscape captured in
  `01/04/07/08-ipad-{portrait,landscape}-{light,dark}.png`.  iPad
  landscape detail layout is clean (single-column, generous gutters,
  pinned dock).  iPad portrait re-graded — see "Discovered in
  re-audit" below for one P2 portrait-specific finding the rotation
  fix surfaced.

## Discovered in re-audit (Chunk 8)

### P1 — Dark mode

- ✅ **#301** Direct keystroke keyboard letter / number keys render
  as blank white tiles in dark mode — **PR (UX Chunk 9)** routed
  `DirectKeystrokeKeyboardView.backgroundFor(role:)` through new
  adaptive tokens `NaruColors.surfaceKey` (light `#FFFFFF` / dark
  `#1A1E25`) for `.standard` letter/number tiles and
  `NaruColors.surfaceKeyAlt` (light `#EAEDF0` / dark `#2C313B`) for
  `.wide` / `.toggle` / `.modifier` tiles.  Two-tier visual hierarchy
  (alpha row vs. system keys) preserved.  Verified in
  `08-direct-qwerty-iphone-dark.png`,
  `08-direct-qwerty-ipad-portrait-dark.png`,
  `08-direct-qwerty-ipad-landscape-dark.png`.

- ✅ **#302** Compose `TextEditor` background hard-coded
  `Color.white.opacity(0.74)` reads as a stark bright rectangle in
  dark mode — **PR (UX Chunk 9)** replaced the hardcoded fill with
  `NaruColors.surfaceEditor` (light `#FFFFFF` / dark `#1A1E25`,
  matching BRANDING.md §7 `Surface`).  Opacity hack dropped — the
  adaptive system color already has the right contrast at full
  alpha.  Verified in `04-profile-selected-iphone-dark.png`,
  `07-compose-text-iphone-dark.png`,
  `12-incoming-clipboard-iphone-dark.png`.

### P2 — iPad portrait pill stacking

- ✅ **#303** iPad portrait first-launch action-row pills wrap their
  labels vertically ("Ch / ec / ks") — **PR (UX Chunk 9)** wrapped
  the regular-width header in `ViewThatFits(in: .horizontal)` so the
  inline `regularHeader` is preferred when the detail column has
  room and the stacked `compactHeader` is automatically substituted
  when it doesn't (iPad portrait with sidebar visible).  No width
  thresholds to maintain.  Verified in
  `01-firstlaunch-ipad-portrait-light.png` /
  `01-firstlaunch-ipad-portrait-dark.png` —
  Checks, Connect, PiP Watch, and the "None" status badge no longer
  cram into ~50pt buckets.

### Coverage gaps still open

- **iPhone landscape** screenshots were never captured.  Sustained-
  terminal use over cellular is the founder workflow but the harness
  only drives portrait + iPad orientations.  Adding `.landscapeLeft`
  iPhone variants is a small extension if a future audit needs them.
- **PiP active streaming** — captured the PiP-watch-disabled empty
  case (#13) and the all-set onboarding-done case (#16, which seeds a
  `.watching` PiP session) but no live framebuffer.  Renderer
  validation against a real RFB framebuffer remains a manual
  device-test row in the constitution §VI matrix.

## Top 5 quick wins (post-Chunk 8 list)

These are the things a single-day follow-up agent could close.

- ✅ **#301** Route Direct-keyboard key backgrounds through
  `NaruColors` so dark mode actually shows letter labels.  P1.
  Closed by **UX Chunk 9**.
- ✅ **#302** Replace `Color.white.opacity(0.74)` on the compose
  `TextEditor` with an adaptive token — fixes the bright rectangle in
  dark mode.  P1.  Closed by **UX Chunk 9**.
- ✅ **#303** Defer / gate the empty-state pill row on iPad portrait
  so it stops stacking labels vertically on the first-launch screen.
  P2.  Closed by **UX Chunk 9** (`ViewThatFits` fallback).
- (Coverage) Add iPhone landscape captures to the audit harness for
  the founder's actual sustained-terminal workflow.
- (Coverage) Add a real-framebuffer fixture so PiP active and
  in-session compose can be vision-judged.

## Original audit (verbatim, from `chore/ux-audit-screenshots`)

The original audit lives at
`origin/chore/ux-audit-screenshots:artifacts/ux-audit/PUNCH_LIST.md`
— retrieve via `git show ...:artifacts/ux-audit/PUNCH_LIST.md`.  The
resolution table above mirrors every original finding by number.
