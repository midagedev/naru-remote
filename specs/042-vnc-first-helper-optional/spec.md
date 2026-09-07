# Feature Specification: VNC-First, Helper-Optional Presentation

**Feature Branch**: `042-vnc-first-helper-optional`
**Created**: 2026-09-07
**Status**: Implemented 2026-09-07 — founder approved the principles ("진행해줘"); Rounds A–E landed (copy and hierarchy, marker + once-per-session notice, pointer mode on the wire with the cursor off in trackpad mode, pinch fix, VNC framebuffer requests parked while helper video is primary, per-profile transport pin). Gates: `swift test` App 718 / Core 674 / FakeRFBServerKit 69 / Kit 170 green, iPhone simulator build green. **Open — founder device pass** (SC-2 one cursor + pinch over the whole viewport, SC-3 `nettop` shows `screensharingd` quiet while video is primary) and US-1 acceptance 2 (the profile editor still shows a "Naru Helper" section with `NaruHelper --pair` copy — not yet moved out of the add form).
**Product**: Naru Remote
**Input**: Founder, 2026-09-07, after the first end-to-end helper-video
session on a physical iPhone against the spec 041 menu bar app. Three
observations and one product decision, in the founder's words:

> "커서 어긋난 곳이 화살표 두개도 보이고 탭한곳도 다른곳이 클릭되, 나는
> 트랙패드 모드 기준 그리고 연결도중에 헬퍼가 켜진건지 안켜진건지 알기
> 어렵다."

> "나는 이 앱이 꼭 헬퍼 앱을 깔아야만 한다는 오해가 생기는걸 막고 싶어.
> 최대한 vnc기본 사용이 가능하다는걸 드러내고, 헬퍼는 꼭 필요하면 쓰는
> 정도로 ui를 정리하고 싶거든 … 헬퍼는 시스템에 설치하고 허용해주고 하는
> 단계가 너무 위험해보여서 앱 자체의 허들이 될까봐 걱정이 되는거야"

> "기본은 vnc로 별도로 표시할 필요 없고 헬퍼모드일때 추가 표시를 두고
> 싶고. 추가로 앱에서 qr버튼을 눌렀을때 이건 도우미 정도이고 일반 vnc정보
> 입력해서 호스트 등록이 가능하다고 잘 드러났으면 좋겠어"

A "split VNC and helper into separate host cards" alternative was raised
and rejected in the same conversation (see §Rejected alternative).

## Problem

Specs 040 and 041 made the helper easy to pair and easy to run. In doing
so the phone's surfaces started to *read* as if the helper were required:

1. **The add path leans on the QR.** The empty home shows "Add a Computer"
   and "QR 찍어 추가하기" as equal-weight buttons; the scanner screen speaks
   only of Naru Helper ("Open Naru Helper on your Mac…", "Get Naru Helper
   from GitHub") and never says a plain VNC address is enough. The pairing
   confirmation lists helper ports with the same weight as the VNC port.
2. **The session says nothing about transport.** Whether frames come from
   VNC or from helper video is invisible; a silent fallback to VNC (spec 007
   health `.stalled/.failed/.fallbackToVNC`, or a start refused with
   `permissionMissing`) leaves the user guessing — measured 2026-09-06 when
   a "5 fps helper session" turned out to be VNC because the Debug helper
   had no Screen Recording grant.
3. **Helper video behaves differently from VNC.** ScreenCaptureKit bakes
   the Mac's pointer into the frame (`showsCursor = true`) while trackpad
   mode draws Naru's own cursor, so two arrows appear ~100 ms apart and a
   tap (which lands at *Naru's* cursor by spec 003) looks like a misclick.
   Pinch zoom did not work in the founder's helper-video session. The VNC
   framebuffer stream keeps flowing (~420 KB/s measured) underneath the
   video, doubling bandwidth for nothing.

Item 1 is a positioning risk: the helper's install → Accessibility →
Screen Recording chain is the scariest sequence in the product, and a
user who believes it is mandatory may leave before the first VNC connect.
Items 2 and 3 are why the founder reached for "separate modes" — the modes
already *feel* separate because they behave differently and no surface
says which one is active.

## Direction (principles this feature enforces)

These bind every surface listed below and are the review criteria for the
plan's tasks.

- **P1 — VNC is the product.** Adding a computer by host, port, and VNC
  password is the primary path on every entry surface. It is complete
  without the helper (constitution: "Helper is optional in MVP").
- **P2 — No transport badge in the default case.** A VNC session shows
  nothing about transport. Only when helper video *is carrying frames*
  does the session show an additional, small, non-modal marker.
- **P3 — Fallback is announced once, with a reason.** When helper video
  was expected (profile has a helper pairing) and the session is on VNC,
  the user is told once, in one line, from the fixed catalog (permission
  missing, helper offline, stream stalled, revoked). Never a blocking
  alert.
- **P4 — The QR is an accelerator, not a gate.** Everywhere the QR/pairing
  path appears it is framed as "if you also run Naru Helper on the Mac";
  the same surface offers manual VNC entry in one tap.
- **P5 — Behaviour parity.** In helper-video mode every gesture and every
  cursor rule of the VNC session applies unchanged: one cursor, trackpad
  tap at Naru's cursor, pinch/pan/double-tap, dock and keyboard.
- **P6 — One card per computer.** A computer is one profile with one
  credential set; transport is a property of the session, optionally
  pinned per profile, never a second card.

## Rejected alternative

**Separate host-list entries for "VNC mode" and "Helper mode".** Rejected
2026-09-07 (lead assessment, founder agreed by redirecting to the
principles above). Two cards would duplicate profile, VNC password, helper
token and history; one QR scan would have to create or update two cards;
and the user would be choosing a transport *before* connecting, which is
exactly when the helper's availability is unknown. The legitimate need
behind the proposal — knowing which transport is live and being able to
force VNC — is met by P2/P3 and FR-006.

## User Scenarios & Testing

### User Story 1 — Add a computer without ever hearing about the helper (P1)

A new user opens Naru, taps **Add a Computer**, types a Tailscale MagicDNS
name or private address, port 5900 and the Screen Sharing password, and
connects. Nothing on the empty home, the add form, or the first session
mentions the helper except one secondary line on the home that offers the
QR path.

**Acceptance**
1. **Given** an empty home, **When** it renders, **Then** "Add a Computer"
   is the single primary action and the QR path is a secondary, smaller
   affordance whose label names it as optional ("Have Naru Helper on the
   Mac? Add by QR").
2. **Given** the add form, **When** it renders, **Then** it contains no
   helper field, helper hint, or helper link.
3. **Given** a VNC-only profile, **When** the session is live, **Then**
   there is no transport marker anywhere in the viewport chrome (P2).

### User Story 2 — The QR screen makes the manual path obvious (P4)

A user taps the QR affordance out of curiosity. The screen explains in
one sentence that this is for Macs running the optional Naru Helper, and
offers **Enter VNC details instead** as a visible action on the same
screen.

**Acceptance**
1. **Given** the scanner screen, **When** it renders, **Then** the first
   text line states the helper is optional and the plain-VNC path exists,
   and a button/link leads to the manual add form in one tap.
2. **Given** the pairing confirmation, **When** it renders, **Then** the
   VNC endpoint is the headline row and helper details are collapsed
   under a "Helper (optional)" disclosure; the constitution guarantee line
   ("Basic viewing keeps working without the helper") stays.

### User Story 3 — Helper video is marked only when it is live (P2, P3)

A user with a paired helper connects. While frames come from helper
video a compact marker (e.g. `▶ Helper`) sits in the viewport corner;
when the session is on VNC the marker is absent. If helper video was
expected and the session is on VNC, a one-line notice with the catalog
reason appears once per session and can be dismissed; tapping it opens
the profile's diagnostics.

**Acceptance**
1. **Given** helper video carrying frames, **When** the viewport renders,
   **Then** the marker is visible and does not occlude the input dock or
   the trackpad cursor.
2. **Given** a start refused with `permissionMissing`, **When** the
   session falls back to VNC, **Then** the notice reads from the fixed
   catalog ("Helper video off — Mac needs Screen Recording permission")
   and no raw error text or address appears (constitution §IV).
3. **Given** helper video stalls mid-session and the runner falls back,
   **Then** the marker disappears and the same one-line notice appears
   with the "stream stalled" reason.

### User Story 4 — One cursor, same gestures, in helper video (P5)

In trackpad mode over helper video the user sees exactly one arrow:
Naru's. Pinch zooms, one-finger drag moves the cursor, two-finger drag
scrolls, double-tap toggles zoom — identical to VNC.

**Acceptance**
1. **Given** trackpad mode and helper video, **When** the Mac renders
   frames, **Then** the captured frames contain no system pointer (the
   helper's ScreenCaptureKit configuration sets `showsCursor = false` for
   the session while the phone reports trackpad mode; direct-touch mode
   may keep it).
2. **Given** helper video, **When** the user pinches, **Then** the view
   zooms about the pinch midpoint and the input mapping follows
   (`ViewportTransform` and the display layer transform agree) —
   verified by the same gesture tests the VNC path uses, run against the
   helper-video preview.
3. **Given** helper video is live, **When** measured over 10 s, **Then**
   the VNC connection carries no framebuffer updates (only pointer/key
   traffic); on fallback, framebuffer requests resume within one update
   cycle.

### User Story 5 — Pin a computer to VNC (P6)

A user who does not want helper video on a given Mac sets the profile's
**Screen transport** to **VNC only**. The helper text bridge is unaffected.

**Acceptance**
1. **Given** the profile editor, **Then** it offers "Screen transport:
   Automatic / VNC only" (no "helper only" — the helper cannot be
   guaranteed present).
2. **Given** "VNC only", **When** connecting, **Then** no helper video
   start request is sent, no marker or notice appears, and the text
   bridge still works.

## Functional Requirements

- **FR-001** Empty home and connection grid present manual add as the
  primary action; the QR path is secondary and labelled optional. Copy
  never states or implies the helper is required.
- **FR-002** The scanner screen's first line states the helper is
  optional and offers manual VNC entry in one tap; error copy stops
  referring to `NaruHelper --pair` (spec 041 replaced the CLI) and names
  the menu bar app's **Pair with iPhone…** instead.
- **FR-003** The pairing confirmation shows VNC endpoint first and helper
  details under a disclosure.
- **FR-004** `VisualTransportMode` is surfaced to the session view; the
  view renders a marker only for `.helperVideo`. No marker for `.vnc`.
- **FR-005** A once-per-session fallback notice with a fixed-catalog
  reason is shown when the profile has helper video enabled and the
  transport is `.vnc` because of a start refusal or a mid-session
  fallback. Reasons are `HelperVideoFailureCode` values mapped to
  catalog strings; no free text.
- **FR-006** `ConnectionProfile.helperVideo` gains a user-visible
  transport preference (`automatic` / `vncOnly`); `vncOnly` suppresses
  start requests and notices. Existing profiles default to `automatic`.
- **FR-007** The helper video start request carries the phone's pointer
  mode; the helper sets `SCStreamConfiguration.showsCursor` to `false`
  when the mode is trackpad. A mode switch mid-session re-issues the
  configuration without restarting the stream where the API allows,
  otherwise restarts it.
- **FR-008** While `.helperVideo` is active the RFB client stops issuing
  `FramebufferUpdateRequest`s after the session's first full frame has
  been delivered (that one frame is the fallback picture and the source of
  the input coordinate space; helper video is selected before the RFB
  handshake, so without it a helper-video session would never hold a
  framebuffer) and resumes with a full (non-incremental) request on
  fallback. The RFB connection stays open for pointer, key, and clipboard.
  Amended 2026-09-07 during Round D authoring: the original "incremental
  or full" wording contradicted the steady-state pin in
  `HelperVideoPreviewGestureTests`.
- **FR-009** Pinch, pan, double-tap zoom, and trackpad gestures over the
  helper-video preview go through the same `ViewportTransform` path as
  the Metal framebuffer view; the display-layer transform is derived
  from that transform, not maintained separately.
- **FR-010** No new user-content logging. The marker, notice, and
  transport preference are catalog values only.

## Success Criteria

- **SC-1** A first-time tester given only the phone app and a Mac with
  Screen Sharing enabled adds and connects without opening the helper
  page (moderated test, 3 of 3).
- **SC-2** In a helper-video trackpad session the founder sees one
  cursor and pinch zoom works ("이제 하나만 보이네" or equivalent).
- **SC-3** With helper video live, RFB framebuffer bytes over 10 s are
  0; total downstream bandwidth drops by at least the VNC share measured
  today (~420 KB/s on the founder's Mac).
- **SC-4** A permission-missing helper produces the one-line notice
  within 2 s of session start on iPhone, verified with `FakeRFBServer` +
  a fake helper video transport returning `permissionMissing`.

## Verification matrix (iPhone first, constitution §VI)

| Path | Surface | How |
|---|---|---|
| iPhone simulator | Empty home, scanner, confirmation copy | XCUITest screenshots under `artifacts/screenshots/vnc-first/`; vision verdict on hierarchy (primary vs secondary weight) |
| iPhone simulator | Marker absent on VNC, present on helper video, notice on fallback | `FakeRFBServer` + fake helper video transport fixtures; XCTest on `NaruRemoteAppModel` snapshot + XCUITest identifiers |
| Core | FR-008 framebuffer request gating | `FakeRFBServerKit` integration test counting update requests per transport state |
| Kit | FR-007 `showsCursor` follows pointer mode | `NaruHelperKitTests` on the configuration policy |
| Device | One cursor, pinch parity, bandwidth | Founder pass on iPhone 15 Pro Max over Tailscale; `nettop` on the Mac for SC-3 |
| iPad | Layout of marker/notice | Graceful scaling check only |

## Out of scope

- Helper install/onboarding redesign on the Mac (spec 041 residuals).
- Audio transport (proposed spec, not yet written).
- Quality-bucket selection (`.readability` 960 px default) — tracked in
  `NEXT_STEPS.md`; a separate spec.

## Open questions

1. Marker form: text (`Helper`) vs glyph only. Vision round decides.
2. Whether direct-touch mode should also hide the baked cursor (the
   finger covers the target; the Mac pointer is the only feedback).
   Default: keep it visible in direct-touch.
3. FR-007 without a stream restart depends on `SCStream.updateConfiguration`
   behaviour on macOS 14; research task in the plan.
