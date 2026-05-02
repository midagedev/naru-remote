# Naru Remote — UX & Design Audit (2026-05-02)

Captured on iPhone 17 Pro / iOS 26.2 + iPad Pro 13" / iOS 26.2 simulator.
Total screenshots: 34. Coverage: 14 app states (10 iPhone-only + 4 iPad parities) × light/dark; many states under-coverage because the dark-mode launch arg is silently ignored and several "different" screens render the exact same fixture.

> Open every "iphone-light" / "iphone-dark" pair in a diff tool — they are byte-identical except for the clock. The dark theme has not been verified by these screenshots.

## P0 — Critical (block ship)

### #001 Dark mode is not actually applied — every "dark" screenshot is identical to its "light" pair
- **Where**: every `*-dark.png` under `artifacts/screenshots/ux-audit/`. Driver: `NaruRemote/UITests/UXAuditScreenshotsUITests.swift:516-527` (`applyColorMode`). Theme baseline: `NaruRemote/App/AppShell/NaruRemoteAppShell.swift:179` and `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift:75`.
- **Symptom**: The audit harness sets `-AppleInterfaceStyle Dark` as a launch argument; that key is a macOS user-default, not an iOS-app flag, so iOS silently ignores it and the app falls back to the device's `.light` system style. Even if the flag worked, `NaruRemoteAppShell` and `RemoteInputDockView` paint hard-coded RGB backgrounds (e.g. `Color(red: 0.96, green: 0.97, blue: 0.96)`) that do not adapt — so dark mode is unimplemented in code, too.
- **Fix sketch**: (a) In the test harness, use `app.launchArguments += ["-NSRequiresAquaSystemAppearance", "NO"]` plus an in-app override hook (e.g. read a `NARU_TEST_OVERRIDE_INTERFACE_STYLE` env var inside `NaruRemoteApplication` and call `window.overrideUserInterfaceStyle = .dark`), or wrap the root view in `.preferredColorScheme(.dark)` from a debug-only environment switch. (b) Replace the hard-coded RGB surfaces with adaptive `Color(.secondarySystemBackground)` / Asset Catalog colors keyed to the `BRANDING.md` light + dark palettes. Re-run audit and confirm the two PNGs in each pair actually differ.

### #002 iPad landscape screenshots are saved 90° rotated — content runs sideways
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-ipad-landscape-light.png`, same for `-dark`, and `04-`, `07-`, `08-` ipad-landscape variants. Driver: `NaruRemote/UITests/UXAuditScreenshotsUITests.swift:362-415` (`testIPadStates`).
- **Symptom**: `XCUIDevice.shared.orientation = .landscapeLeft` rotates the simulator UI but `XCUIScreen.main.screenshot()` still returns the framebuffer at the device's portrait pixel orientation, so the saved PNG has the system clock on the right edge and every label rotated 90°. This makes vision review of iPad parity impossible and obscures whether the iPad layout has its own bugs.
- **Fix sketch**: Either rotate the captured `UIImage` 90° before writing PNG (e.g. `UIImage(cgImage: cg, scale: 1, orientation: .right)` then re-encode), or drive screenshots through `app.windows.firstMatch.screenshot()` which honors the current interface orientation. Add a single iPad portrait baseline so we have an unrotated comparison until the rotation lands.

### #003 First Run sheet bleeds through onto the iPad detail column — split-view collision
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-ipad-landscape-light.png` (top half is the sidebar/sheet, bottom half is detail with dock); same for 04-ipad. Layout owner: `NaruRemote/App/AppShell/NaruRemoteAppShell.swift:39-181` (`NavigationSplitView` with `OnboardingGuideView` rendered inside the detail's `ScrollView`).
- **Symptom**: On iPad the sidebar list is visible at the top while the detail column simultaneously renders the First Run checklist, hero text, action pills, dock, and a black "PiP after first frame" HUD bar. The two columns visually fight for the same vertical band; no clear focus hierarchy. (The 90° rotation in #002 makes this more obvious — the audit reviewer cannot tell whether this is an XCUITest harness problem or a SwiftUI layout problem until the orientation is fixed.)
- **Fix sketch**: Verify on a non-rotated iPad capture; if the duplication is real, the OnboardingGuideView should be either a sidebar item or a top-of-detail dismissable banner — not a full-section panel that competes with the session viewport. Ensure `SessionViewportView` is the dominant element on iPad detail per `BRANDING.md` §9.2.

### #004 Hero title "Naru Remote" is clipped on the left edge in the empty session viewport
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png` (and -dark). Renders at `NaruRemote/App/Features/SessionViewer/SessionViewportView.swift:124-133`.
- **Symptom**: The first character of "Naru Remote" and the subtitle "Private Network Remote Desktop" run off the left edge of the screen — only "aru Remote" / "rivate Network..." is visible. SessionViewportView's outer `VStack(alignment: .leading, spacing: 12)` lacks a leading horizontal padding, and `safeAreaInset` for the dock pushes content but the title row sits flush against the screen edge.
- **Fix sketch**: Add `.padding(.horizontal, 16)` to the outer `VStack` in `SessionViewportView.body`, or wrap the detail `ScrollView` content in a `.padding(.horizontal, 16)`. Verify all detail-column rows respect the same gutter.

### #005 Three-pill action row stacks Label icon-over-text, looks like sneaker silhouettes; "No Session" wraps mid-word
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png`, `04-profile-selected-iphone-light.png`. Code: `NaruRemote/App/Features/SessionViewer/SessionViewportView.swift:137-186`.
- **Symptom**: `Label("Checks", ...).buttonStyle(.bordered)` + `Label("Connect", ...).buttonStyle(.borderedProminent)` + `Label("PiP Watch", ...).buttonStyle(.bordered)` are placed in an `HStack(spacing: 10)` next to the title. On compact width the buttons each become tall pills with the system image stacked above the title (because Label content overflows horizontally and SwiftUI breaks the label vertically), giving a strange three-shoes silhouette. Adjacent `Label("No Session", ...)` wraps to "No Sess / ion" because nothing constrains its width.
- **Fix sketch**: On compact width use `.labelStyle(.iconOnly)` for Checks + PiP Watch and keep the prominent Connect button labeled, OR move the action row below the title row so each button gets the full width to lay out horizontally. Set `.fixedSize(horizontal: true, vertical: false)` on the status `Label` to prevent mid-word wrap, or shorten copy to "None".

### #006 Public-IP profile has only an icon to convey "this is the advanced public path" — no copy warning
- **Where**: `artifacts/screenshots/ux-audit/14-sidebar-multiple-iphone-light.png` (the `Public test` row at `203.0.113.5:5900`). Code: `NaruRemote/App/Features/ConnectionHub/ProfileListView.swift:130-151`.
- **Symptom**: Constitution principle II requires public VNC to be an "advanced/manual path with explicit warnings". The list shows only a tiny `exclamationmark.triangle` SF Symbol in front of the host — no inline subtitle like "public address — advanced", no color, no row tint. A user scanning the list cannot tell at a glance which target is the safe Tailnet path versus the public IP. Same icon size as the neutral globe means the warning reads as decoration.
- **Fix sketch**: Add a dedicated "Public" caption-row beneath the host:port line for `.advancedManualPublicEndpoint` profiles, tinted Coral `#E85D4F` (light) / `#FF756B` (dark) per `BRANDING.md` §7. Optionally tint the icon background as well. Block tap-to-connect until the user has acknowledged the warning once per session (matches how Direct mode warns).

### #007 "Diagnostics populated" and "Onboarding progress" screenshots show no diagnostics and no progress
- **Where**: `artifacts/screenshots/ux-audit/05-diagnostics-populated-iphone-light.png`, `06-onboarding-progress-iphone-light.png`. Driver: `NaruRemote/UITests/UXAuditScreenshotsUITests.swift:106-170`.
- **Symptom**: Visually these two screenshots are byte-identical to `04-profile-selected-iphone-light.png` — same checklist, same "Run Checks" pill, same "No Session" status, no diagnostic rows expanded, no progress beyond the first checkmark. The audit fixture seeds a profile but never actually triggers `runConnectionChecks()` and never advances onboarding. Reviewers cannot judge whether the diagnostics list reads correctly because it is not on screen.
- **Fix sketch**: Update the harness so state #05 taps the `Run Checks` pill, waits for `DiagnosticSummaryView` rows to populate (mock or real), and captures only after rows render. State #06 should drive onboarding to the "Compose locally" step (Connection checks done, "Open a remote session first." active) so the screenshot exercises a different cell mix.

### #008 No persistent IME-incompatibility cue on Direct mode after the entry warning is dismissed
- **Where**: `artifacts/screenshots/ux-audit/08-direct-qwerty-iphone-light.png`, `09-direct-special-iphone-light.png`, `11-modifier-locked-iphone-light.png`. Code: `NaruRemote/App/Features/RemoteInputDock/DirectModeBadge.swift:1-60`, `NaruRemote/App/Features/RemoteInputDock/DirectModeWarningDialog.swift:1-92`.
- **Symptom**: The first-entry alert in `10-direct-warning-iphone-light.png` is good copy ("IME input… will not work"), but once dismissed the only ambient signal that Direct is active is a small blue "Direct mode" pill in the toolbar and dock title — no IME-specific warning. A returning user who turned Direct on yesterday will never see that Korean/Chinese/Japanese typing is unsafe; they will tap on the QWERTY page, see a familiar-looking soft keyboard, and assume IME works. The constitution explicitly requires the "IME may not work" warning for Direct.
- **Fix sketch**: Either keep the IME warning text as a 1-line caption inside the dock header whenever Direct is active (e.g. "Direct — IME off"), or paint the `DirectModeBadge` with the Coral / amber accent so it reads as a state-warning rather than a neutral mode indicator. Keep the dialog as the first-entry-per-session education; the persistent badge should still tell the truth on its own.

### #009 Korean keyboard pushes the First Run checklist clipping the bottom row in Compose
- **Where**: `artifacts/screenshots/ux-audit/07-compose-text-iphone-light.png`. Layout: `NaruRemote/App/AppShell/NaruRemoteAppShell.swift:64-128` (detail-column `ScrollView` with onboarding + viewport + diagnostics inside, dock pinned via `safeAreaInset`).
- **Symptom**: When the Korean keyboard is up, the available height for the detail column shrinks; the First Run checklist's last row "PiP Watch / Available after first frame." gets clipped to "Wai…" / "PiP Wa…" mid-glyph. The compose textfield + Send button still fit, but the screenshot above the keyboard wastes roughly 30% of the visible area on a partially-truncated checklist instead of letting the user focus on the text they are composing.
- **Fix sketch**: When the keyboard is presented, collapse `OnboardingGuideView` to a 1-line summary banner ("First Run · 1 of 4 done — Run Checks") via `@FocusState` on the text editor, restoring the full checklist on blur. Alternatively float the dock above a blurred backdrop instead of pushing layout — avoids the chase-the-keyboard reflow.

## P1 — Important (post-MVP polish)

### #101 "Add Profile" appears twice on first launch — toolbar plus checklist CTA pill
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png`, `04-profile-selected-iphone-light.png`. Code: `NaruRemote/App/AppShell/NaruRemoteAppShell.swift:55-62` (toolbar) + `NaruRemote/App/Features/Onboarding/OnboardingGuideView.swift:27-31, 61-70` (checklist next-action pill).
- **Symptom**: The top-right toolbar shows "Add Profile" text in blue, and the First Run row shows another "Add Profile" pill on the right side of the row. Both invoke the same sheet. Two CTAs at the same level inflate the visual noise and create a "which one is real?" moment for first-time users.
- **Fix sketch**: Drop the toolbar's "Add Profile" until at least one profile exists, OR hide the OnboardingGuideView CTA pill once the toolbar button is reachable. The checklist row already shows the `firstActionableStep` text on the right — that read-only label is enough; the action belongs in the toolbar.

### #102 Profile editor shows no validation, no "Test" affordance, lets user save an empty form
- **Where**: `artifacts/screenshots/ux-audit/02-profile-editor-empty-iphone-light.png` (Save button is enabled with empty fields). Code: `NaruRemote/App/Features/ConnectionHub/ProfileEditorView.swift:1-220`.
- **Symptom**: Save is tappable on an empty form; there is no inline error when the user lands in the host field, no `isValid` gate, no "Test connection" button, no host-format hint. Port is shown as a bare "5900" without a "Port" label. Constitution principle III ("Verification before confidence") implies the profile creation surface should surface basic reachability before persisting.
- **Fix sketch**: Disable Save until name + host are non-empty. Add a "Test" button that runs DNS+TCP+RFB-handshake and renders a one-line outcome ("studio.tailnet.ts.net:5900 reachable, requires VNC password"). Label the port row "Port" and validate `1…65535`.

### #103 PiP-after-first-frame HUD chip is shown even when no session has ever connected
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png` (black bar with `PiP after first frame` near the bottom). Code: `NaruRemote/App/Features/SessionViewer/SessionViewportView.swift:189-220`.
- **Symptom**: The dark "PiP after first frame" affordance hangs underneath the empty viewport even on first launch with no profile selected — it reads like a dead UI chip. PiP Watch is meaningful only after a frame has streamed; rendering the cue before that point is noise.
- **Fix sketch**: Hide or fade the PiP HUD chip until `framebuffer != nil`, or replace its copy with the same gating phrase used by the action row ("Connect first") so the empty state reads as a single intent.

### #104 Three-pill action row + status label run off the right edge on compact width
- **Where**: `artifacts/screenshots/ux-audit/04-profile-selected-iphone-light.png` (status "No Session" wraps; the icon-only pills sit jammed against the right side). Code: `NaruRemote/App/Features/SessionViewer/SessionViewportView.swift:124-187`.
- **Symptom**: On iPhone, four chrome pieces (Checks pill, Connect pill, PiP Watch pill, status Label) are all in the same trailing HStack as the title. There is not enough horizontal room. Status text wraps mid-word (covered by #005), and tapping any of the three buttons would be tight to discriminate (likely <44pt horizontal target).
- **Fix sketch**: Move the action pills below the title row on compact width so they get the full width. Status moves to a small badge under the subtitle. iPad keeps the inline layout.

### #105 Onboarding row labels mix Korean concepts (Tailnet) with English without the explicit Tailscale-affiliation guardrail showing
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png` ("Add a MagicDNS name or private host."). Copy origin: `NaruRemote/Sources/NaruRemoteCore/Onboarding/OnboardingGuide.swift`.
- **Symptom**: First Run mentions "MagicDNS" but never says "this is a Tailscale feature, set it up in your Tailscale app first" — and the constitution forbids implying Naru is officially Tailscale-affiliated. Today the copy is ambiguous in the safe direction (no claim of affiliation), but "MagicDNS or private host" reads as a Naru concept rather than a property of an external Tailnet. Small risk that users believe Naru sets up MagicDNS for them.
- **Fix sketch**: Reword to "Use your Tailscale MagicDNS name (e.g. `studio.tailnet.ts.net`) or any private host you can reach." Add a one-liner subtitle in the empty state that says "Naru does not configure Tailscale — set up your tailnet first."

### #106 Onboarding's "current step" arrow uses Signal Blue but the row is rendered with the same weight as the inactive rows
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png`, `04-profile-selected-iphone-light.png`. Code: `NaruRemote/App/Features/Onboarding/OnboardingGuideView.swift:44-78`.
- **Symptom**: The `firstActionableStep` icon is a teal arrow circle, but the row's title ("Private target") is the same weight + color as the disabled rows below ("Connection checks", "Compose locally", "PiP Watch"). The active/inactive distinction is carried entirely by the icon — a 16pt symbol — which is weak hierarchy.
- **Fix sketch**: Bump the active row's title to `.semibold` + Ink, leave the inactive rows in `.regular` + Muted Ink. Alternatively give the active row a faint `Color.accentColor.opacity(0.06)` background tint.

### #107 Compose / Direct picker repeats the "Direct mode" badge in two places when active
- **Where**: `artifacts/screenshots/ux-audit/08-direct-qwerty-iphone-light.png`, `09-direct-special-iphone-light.png`, `11-modifier-locked-iphone-light.png`. Code: `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift:43-90`, `NaruRemote/App/AppShell/NaruRemoteAppShell.swift:165-178`.
- **Symptom**: When Direct is on, the same "Direct mode" pill renders both at the top of the screen (HUD safe-area inset) and inside the dock header, ~10pt apart vertically because the keyboard pushes the dock up. The HUD copy is meant for when the keyboard is hidden; with the keyboard up they collide.
- **Fix sketch**: Hide the HUD badge whenever the dock badge is on screen (i.e., when the keyboard is presented or `directKeyboard` is rendered). The two badges already have separate accessibility ids — toggle visibility based on `dockBadgeIsVisible`.

### #108 Profile-list selection cue is one tiny green checkmark; weak focus state
- **Where**: `artifacts/screenshots/ux-audit/14-sidebar-multiple-iphone-light.png` (Home NUC has a small green check on the right; the cell is otherwise identical to the unselected rows). Code: `NaruRemote/App/Features/ConnectionHub/ProfileListView.swift`.
- **Symptom**: The selected profile reads almost identically to unselected rows. There is no row tint, no leading accent stripe, no semibold title shift. On a small phone screen this turns selection into a Where's-Waldo task.
- **Fix sketch**: Apply `.listRowBackground(Color.accentColor.opacity(0.08))` to the selected row, or draw a 3pt leading bar in Signal Blue. Keep the green checkmark as a "this is the active session target" badge — but it should not be the only signal.

### #109 No connection-status indicator per profile in the sidebar
- **Where**: `artifacts/screenshots/ux-audit/14-sidebar-multiple-iphone-light.png`. Code: `NaruRemote/App/Features/ConnectionHub/ProfileListView.swift`.
- **Symptom**: Four profiles, no per-row indicator that any of them is reachable, recently failed, or last connected at a particular time. Phone-first users want to know "is this likely to work right now?" before tapping.
- **Fix sketch**: Cache the most recent diagnostic verdict per profile (`reachable`, `unreachable`, `auth-required`, `unknown`) and render a colored dot leading the row. Use the existing diagnostic catalog rather than freeform strings (constitution §IV).

### #110 Modifier-locked state cue ("LOCK" text on shift) is small and uses raw uppercase Latin in a Korean context
- **Where**: `artifacts/screenshots/ux-audit/11-modifier-locked-iphone-light.png` (the shift key shows a small "LOCK" inside the chevron). Code: `NaruRemote/App/Features/RemoteInputDock/ModifierKeyButton.swift`.
- **Symptom**: "LOCK" sits inside the key in tiny caps and is hard to read at a glance; for Korean users who toggled Caps Lock by accident there is no localized hint. The locked-state color shift is also subtle.
- **Fix sketch**: Replace the inline "LOCK" with a thin filled bottom rule under the glyph or a Signal Blue background fill, plus a small VoiceOver-friendly accessibility label. Strip the literal "LOCK" text — the visual state should carry the meaning.

## P2 — Nice-to-have

### #201 Empty viewport copy "Naru Remote / Private Network Remote Desktop" reads like marketing inside the app
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png`, `13-pip-disabled-iphone-light.png`. Code: `NaruRemote/App/Features/SessionViewer/SessionViewportView.swift` (title/subtitle pass-through from `NaruRemoteAppSnapshot`).
- **Symptom**: With no profile selected, the session viewport hero shows the product name and tagline. Per `BRANDING.md` §9.1 the home view should "show 접속 가능한 장비를 고른다 first" — the product name belongs in the App Store, not as the empty-state hero on the home screen.
- **Fix sketch**: When `selectedProfile == nil`, replace the title/subtitle with "Pick a computer" / "Choose a profile from the sidebar to begin." Reserve the product name for a Settings → About row.

### #202 First Run checklist takes the same vertical real estate before and after the user has done anything
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png` vs `04-profile-selected-iphone-light.png`. Code: `NaruRemote/App/Features/Onboarding/OnboardingGuideView.swift`.
- **Symptom**: The 4-row grid is full-height in both states, even after the first row goes Done. There is no "collapse to last row" animation, and the next-step caption duplicates content already inside the grid.
- **Fix sketch**: Once a step finishes, animate it to a 24pt "✓ Step name — Done" row and keep only the active step at full height. Once Done, replace the panel with `OnboardingReadyView`.

### #203 Hairline divider above the dock disappears against the hard-coded mint canvas
- **Where**: `artifacts/screenshots/ux-audit/01-firstlaunch-iphone-light.png` (no visible separation between the viewport area and the dock — the dock's `Color(red: 0.91, green: 0.94, blue: 0.94)` blends into the detail's `Color(red: 0.96, green: 0.97, blue: 0.96)`). Code: `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift:75-79`.
- **Symptom**: The dock and the viewport surface are both ~5% saturation off-white-mint with a 1pt Divider that vanishes. The dock loses its identity as a separate input surface.
- **Fix sketch**: Use the `Hairline` token from `BRANDING.md` (`#D9DEE5`) as a 1pt top border, and pull the dock background off Surface Raised toward the named token in light + dark.

### #204 Send button (paperplane) sits flush to the bottom-right corner of the textfield with no breathing room
- **Where**: `artifacts/screenshots/ux-audit/04-profile-selected-iphone-light.png`, `07-compose-text-iphone-light.png`. Code: `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift:115-139`.
- **Symptom**: Send sits inside the same HStack as the TextEditor with `spacing: 12`; the Send glyph and the editor outer stroke nearly touch on iPhone. Looks cramped.
- **Fix sketch**: Move Send below the editor as a trailing-aligned full-width button on compact width, or increase the stack spacing to 16 and pad the editor's trailing inset.

### #205 Direct QWERTY keyboard's keys lack a visible pressed state in static screenshots — looks identical to system iOS keyboard
- **Where**: `artifacts/screenshots/ux-audit/08-direct-qwerty-iphone-light.png`. Code: `NaruRemote/App/Features/RemoteInputDock/DirectKeystrokeKeyboardView.swift`.
- **Symptom**: At a glance the custom QWERTY page looks identical to the iOS system keyboard — same key shape, same layout, same colors. A user who switched modes by accident will not visually notice. The custom keyboard's only differentiator is the "Direct mode" pill (covered by #008) and the `123` page-toggle behavior.
- **Fix sketch**: Tint the spacebar with a faint accent stripe and label it "Direct space" or replace `123` with an ⇄ glyph that signals "switches to special keys" rather than a generic mode shift. Change the key fill to match `Surface Raised` so the keyboard reads as part of Naru, not iOS.

### #206 iPad layout breathing room is unverifiable
- **Where**: every iPad screenshot in `artifacts/screenshots/ux-audit/` (rotated 90°, see #002).
- **Symptom**: Until #002 lands we cannot judge iPad-specific breathing room, sidebar width, or detail column padding.
- **Fix sketch**: After #002, capture iPad portrait + landscape and re-grade as a P2 sweep.

## Top 5 quick wins
- **#004** Add `.padding(.horizontal, 16)` to `SessionViewportView` outer VStack — fixes hero-text clipping in one diff.
- **#101** Hide the toolbar `Add Profile` button when no profile exists, OR hide the checklist CTA pill when both are reachable — removes duplicate-CTA confusion.
- **#103** Gate the "PiP after first frame" HUD chip on `framebuffer != nil` — kills a phantom UI element on first launch.
- **#108** Add a `Color.accentColor.opacity(0.08)` row background on the selected profile — turns the weak checkmark cue into something a phone user can see.
- **#201** When `selectedProfile == nil`, swap the empty viewport copy from "Naru Remote / Private Network Remote Desktop" to "Pick a computer / Choose a profile from the sidebar to begin." — kills a marketing-hero in the runtime UI.

## Coverage gaps
- Dark-mode visuals are not actually verified anywhere in this audit (#001).
- iPad orientation is unreviewable at all four states (#002, #003, #206).
- Diagnostics list with populated rows was never captured (#007); state #05 is a duplicate of #04.
- Onboarding mid-progress (Connection checks done, Compose locally active) was never captured (#007); state #06 is a duplicate of #04.
- PiP Watch states never reach an active streaming session — `13-pip-disabled-iphone-light.png` is identical to `01-firstlaunch-iphone-light.png` and is therefore not really a "PiP disabled" view, just a "no session" view.
- No screenshots of: error states (DNS fails, RFB handshake fails, auth required), incoming-clipboard banner accept/dismiss, sticky-modifier "armed" intermediate state (only locked is captured), profile-edit (vs add) sheet, public-IP profile selected with the warning UX, `OnboardingReadyView` final affirmation.
- iPhone landscape was never captured at all — sustained-terminal use (the founder's actual workflow per memory) likely happens with the phone rotated.
