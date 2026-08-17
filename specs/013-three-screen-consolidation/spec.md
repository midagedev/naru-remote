# Feature Specification: Three-Screen Consolidation (Retire The Failure Surface)

**Feature Branch**: `013-three-screen-consolidation`
**Created**: 2026-08-18
**Status**: Draft — founder direction 2026-08-18 ("전체 화면 목록이 호스트목록, 신규호스트/호스트 수정, 원격제어 이렇게 세 개만 있어서 깔끔하게 되어야 하는데 호스트 목록과 원격제어 사이에 이상한 화면이 하나 생겨서 자꾸 안 없어지더라고" + "꼭 필요한 걸 호스트 목록으로 합치고 제거하고 싶어 혹은 원격제어 화면에 합치거나")
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
   a session is connecting or live.
2. **Given** the user cancels while connecting, **Then** the existing disconnect
   path returns to the host list unchanged.

## Scope

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

## Residuals

- (fill at implementation time)
