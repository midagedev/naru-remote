# Feature Specification: Three-Screen Consolidation (Retire The Failure Surface)

**Feature Branch**: `013-three-screen-consolidation`
**Created**: 2026-08-18
**Status**: Implemented 2026-08-18 (`35c692d0`); **extended 2026-08-19 with
US-4** after the founder tested build 2 on a physical device and found the
connecting state still reading as a third screen ("실기기 테스트 해보니 여전히
호스트 목록과 원격제어 사이에 접속중 상태에 보이는 추가적인 화면이 남아있네").
Original direction 2026-08-18 ("전체 화면 목록이 호스트목록, 신규호스트/호스트 수정, 원격제어 이렇게 세 개만 있어서 깔끔하게 되어야 하는데 호스트 목록과 원격제어 사이에 이상한 화면이 하나 생겨서 자꾸 안 없어지더라고" + "꼭 필요한 걸 호스트 목록으로 합치고 제거하고 싶어 혹은 원격제어 화면에 합치거나")
**Product**: Naru Remote
**Input**: Lead navigation audit 2026-08-18 (`NaruRemoteAppShell.swift` route map).

## Problem

The product is meant to be three screens: **host list**, **new/edit host**,
**remote control**. The route table already is — `EmptyHome`, `ConnectionGridView`,
and the Operation surface (`NaruRemoteAppShell.swift:596-639`, `:452-471`). But a
fourth screen exists in practice, and it is the one the founder keeps landing on:

1. **Tapping a host card enters the remote-control screen before the connection
   is even attempted** (`beginConnection(to:)` sets `showsOperationSurface = true`
   synchronously, `NaruRemoteAppShell.swift:230-239`). If the connection then
   fails, the user is left on a black viewport covered by the
   `operationRecoveryCard` — "Connection needs attention" with Retry / Edit /
   Diagnostics / Connections (`:263-299`, gated by `showsOperationRecovery`
   `:346-357`). It reads as a third screen between the list and the remote.
2. **It has no automatic exit.** `showsOperationSurface` is set back to false in
   exactly one place in the repository — `returnToConnections()` (`:251-261`) —
   so the card stays up indefinitely while the session is `.failed`/`.closed`
   with no framebuffer.
3. **Its own actions do not clear it.** `Edit` opens the profile editor, and the
   save callback (`:699-709`) neither reconnects nor leaves the surface, so
   fixing the password returns the user to the same card. `Retry` re-fails
   instantly when the cause is unchanged (e.g. no Keychain credential).
4. **It is the only exit.** The viewport's Disconnect button is hidden in
   `.failed`/`.closed` (`SessionViewportView.swift:2229-2237`), and the immersive
   control bar's Connections button auto-hides after 2.4 s, so the card's own
   Connections button is effectively the single way out.
5. **A mid-session drop lands there too.** When the auto-reconnect budget is
   spent the model calls `markFailed` + `clearSessionFrame`
   (`NaruRemoteAppModel.swift:5287-5292`), so a live session degrades into this
   same card.

Of the card's four actions, **Edit and Connections already exist on the host
list**, and Diagnostics has no entry point there at all. Only the failure
message and Retry carry information the list does not have.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A Failed Connection Returns To The Host List (Priority: P0)

**Acceptance Scenarios**:

1. **Given** the user taps a host card and the connection fails (no framebuffer
   ever arrives), **When** the session reaches `.failed` or `.closed`, **Then**
   the app returns to the host list by itself — no user action, no intermediate
   card — and the remote-control screen is not shown for that attempt.
2. **Given** the host list after such a failure, **When** the user looks at that
   host's card, **Then** the card shows the failure inline: the same
   app-authored reason the recovery card used to show (e.g. "Credential
   unavailable"), plus a **Reconnect** action. No new failure copy is invented.
3. **Given** a live session that drops and exhausts its auto-reconnect budget,
   **When** the session is marked failed, **Then** the same return-and-annotate
   behavior applies (the founder's chosen rule: failures belong to the list).
4. **Given** the failure is shown on the card, **When** the user taps the card
   (or Reconnect), **Then** a fresh connection attempt starts exactly as a normal
   tap does, and the failure annotation clears while connecting.
5. **Given** the user edits the failing host and saves, **When** the editor
   closes, **Then** the user is on the host list with the updated card — never on
   a stale failure surface.
6. **Then** `operationRecoveryCard` and `showsOperationRecovery` no longer exist:
   there is no state in which a recovery card overlay renders.

### User Story 2 — Diagnostics Lives On The Host Card (Priority: P0)

**Acceptance Scenarios**:

1. **Given** the host list, **When** the user opens a card's actions menu (the
   existing "···" menu, `ConnectionGridView.swift:144-172`), **Then** it offers
   **Diagnostics** alongside Edit and Delete, opening the same diagnostic detail
   sheet the capsule opens.
2. **Given** the remote-control screen, **When** the session is connecting,
   authenticating, active, degraded, or reconnecting, **Then** the diagnostic
   capsule still renders; failed/closed no longer occur on that surface.

### User Story 3 — The Remote Screen Exists Only For A Session (Priority: P1)

**Acceptance Scenarios**:

1. **Given** any app state, **Then** exactly one of three surfaces is on screen:
   the host list (or its empty-state CTA), the profile editor sheet, or the
   remote-control screen — and the remote-control screen is on screen only while
   a session is live. *(Amended by US-4 on 2026-08-19: this originally read
   "connecting or live", and that "or connecting" is exactly what the founder
   met on device as a third screen.)*
2. **Given** the user cancels while connecting, **Then** the session ends and the
   host list — which never left — stays put (US-4).

### User Story 4 — Connecting Belongs To The Host List (Priority: P0)

Added 2026-08-19. US1 retired the *failure* surface; the device pass showed the
same complaint survives in the `.connecting` window. Tapping a card opened the
remote-control screen immediately, before any frame existed, so the user met a
placeholder ("Waiting for first frame") under a full-height pinned input dock —
a layout that resembles neither the host list nor a live session, and therefore
reads as a third screen. Founder decision (2026-08-19, presented as two
options): **the host list owns connecting.**

**Acceptance Scenarios**:

1. **Given** the user taps a host card, **When** the session is connecting or
   authenticating and no frame has arrived, **Then** the host list stays on
   screen and that card shows progress plus a Cancel control.
2. **Given** a connect is in progress, **When** the first frame arrives, **Then**
   the remote-control screen opens with the remote screen already filling it.
3. **Given** a connect is in progress, **When** the user taps Cancel on the card,
   **Then** the session ends and the list stays put.
4. **Given** any session state, **Then** the remote-control screen is never on
   screen without a remote screen to show (except under the screenshot pin).
5. **Given** a live session drops mid-stream, **When** the state becomes
   `.failed`/`.closed`, **Then** the user returns to the list even though a stale
   framebuffer is still in memory — no frozen screen.

**Structural note**: the recurrence mechanism matters more than the fix. Both
occurrences came from the same shape — a view-local route flag set on tap
(`showsOperationSurface = true`) and corrected afterwards once the session
caught up. That flag is deleted. `RemoteControlSurfacePolicy` in
`NaruRemoteCore` now *derives* which surface is on from
`(sessionState, hasFramebuffer)`, so no code path can put an empty
remote-control screen on screen.

## Scope

**In (2026-08-19, US-4)**: `RemoteControlSurfacePolicy` as the single owner of
surface selection; deletion of `showsOperationSurface` and its correction
handlers; `ConnectionGridCardConnecting` derivation plus the card's progress row
and Cancel button; retirement of the compose-while-connecting UI test whose
window no longer exists.

**In**: automatic return to the host list on `.failed`/`.closed` without a
framebuffer; per-card failure annotation + Reconnect on `ConnectionGridCard`;
Diagnostics entry in the card actions menu; deletion of `operationRecoveryCard`,
`showsOperationRecovery`, and the recovery card's accessibility identifiers;
diagnostic-capsule gating; screenshot-harness hook so UI captures that
deliberately sit on a failed session keep working.

**Out of scope**: redesigning the host card's visual language beyond the failure
row; changing reconnect policy or budgets; auto-retry; changing the profile
editor; helper/PiP surfaces.

## Verification Matrix

- Unit (`swift test`, US-4): `RemoteControlSurfacePolicyTests` — connecting and
  authenticating without a frame stay on the host list; `.active` (only
  reachable through `markFirstFrameReceived`) opens remote control; terminal
  states return to the list even with a stale frame; the screenshot pin still
  mounts the surface; and a table test that no state shows remote control
  without a frame. `ConnectionGridCardConnectingDerivationTests` — right profile
  only, cleared once a frame exists, label from a fixed vocabulary rather than
  session text (constitution §IV).
- Unit (`swift test`): the return-to-list routing predicate (failed/closed with
  no framebuffer ⇒ leave the operation surface; connecting/active/reconnecting ⇒
  stay); card failure derivation from the session snapshot (right profile only,
  cleared while connecting); capsule gating; the replaced navigation contract in
  `NaruRemoteAppShellNavigationTests` (this spec deliberately retires the
  `showsOperationRecovery` assertions — the old contract is being removed, not
  weakened).
- iPhone simulator screenshots: host list with a failed card, and the
  remote-control screen with no recovery overlay.
- iPad simulator: same two captures at regular width.
- **Physical-device residual**: fold into the existing paired-device pass — a
  real failed connect (wrong password) and a real mid-session drop.

### US-4 gates (2026-08-19)

- `swift test`: 1568 tests / 26 skipped / 0 failures.
- `UXAuditScreenshotsUITests.testConnectingStaysOnHostList_dark`: asserts the
  grid stays, the card reports progress with a Cancel button, and neither the
  session viewport nor the accessory strip is mounted. Capture:
  `artifacts/screenshots/ux-audit/20-connecting-on-host-list-iphone-dark.png`
  (read by the lead — spinner, "Connecting…", Cancel, no third screen). The
  before-state capture is what identified the defect.
- Regression found while verifying and fixed in the same round:
  `ComposeInputResponsivenessUITests` was **red before this work** (11 tests, 20
  failures, reproduced at `548d8ad2`) because its `composeEditor` helper never
  performed the compose-reveal tap a live-session dock requires since spec
  011/012. It is now 10/10; the eleventh test was retired with US-4 (see below).

## Residuals

Gates run by the lead: `swift test` 1565 tests / 26 skipped; iPhone 17 Pro
simulator build clean; `UXAuditScreenshotsUITests` 34/34 including the new
`04b-connection-grid-failed` capture, which was read and shows the reason,
the Unreachable badge, and an inline Reconnect on the host list.

Carried forward:

- **US-4 physical device**: a real connect on the founder's iPhone — the card
  shows progress, Cancel works, and remote control opens on the first frame.
- **Retired with US-4**:
  `ComposeInputResponsivenessUITests.testFocusedConnectingComposeDefersLiveLayoutAfterFirstFrameAndKeepsTyping`
  composed Korean *while connecting* and asserted the editor survived the first
  frame landing underneath it. That window no longer exists for a user, so the
  bug class it guarded ("first syllable, then the live session starts, keyboard
  freezes") is closed by construction. The rationale is left in the test file at
  the deleted method's position.
- **Physical device**: a real failed connect (wrong password) and a real
  mid-session drop, folded into the paired-device pass in `NEXT_STEPS.md`.
- **Pre-existing, not caused by this feature**: two `NaruRemoteLaunchUITests`
  failures reproduce at `e249df1d` — the landscape dock sits 186 pt above the
  keyboard (the test wants < 96) and the startup-glance test cannot find a
  grid card. Tracked in `NEXT_STEPS.md`.
- **Flaky**: `PointerEventTapTests.testSendTapAtRecordsOnlySafeOutboundInputDiagnostics`
  failed once under full-suite load on the `"512"` privacy assertion and
  passed 3/3 in isolation. Worth a look before release, since the assertion
  guards constitution §IV.
- The failure reason is app-authored English (e.g. "Credential unavailable");
  Korean localization stays the separate P1 String Catalog item.
