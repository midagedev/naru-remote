# Feature Specification: What PiP Watches

**Feature Branch**: `034-pip-framing`
**Created**: 2026-08-25
**Status**: Drafted 2026-08-25.
**Product**: Naru Remote
**Input**: Founder, after spec 033 put PiP one tap away: "특히 버튼 하나로 바로
pip로 쉽게 들어갈 수 있으면 좋겠어 — 그런데 pip 영역을 어떻게 잡을지는 좀
고민이네." Then, on the options: "자동 프레이밍은 일단 옵션으로라도 꼭 넣어야겠다.
내 생각엔 pip 누르면 현재 화면 중심 가고, 롱프레스 하면 영역지정 / 자동프레이밍
설정 가는 정도가 되면 어떨까 싶네."

## Why

PiP entry is now one tap (spec 033). The question that replaces it is what the
floating window shows, and it is sharper than it looks because **PiP is
watch-only**: the app is in the background while the window is up, so whatever
framing PiP takes at entry is the framing the user is stuck with. There is no
"pan it a bit" once you have left.

Two measurements bound the problem.

**The remote screen is far larger than the window.** This Mac serves 3024×1964
(spec 031, direct probe). A PiP window on an iPhone is a few hundred device
pixels wide, so a whole-desktop PiP renders each desktop pixel at roughly a
fifth of a device pixel — terminal text at that scale is not text.

**The app's own zoom ceiling is already at the legibility point.** Both
`SessionViewportView.maxZoomScale` and `PiPWatchViewport.maximumZoomScale` are
**4.0**, and 3024 ÷ 4 = 756 framebuffer pixels of crop width — about what 80
columns of terminal type needs. So inheriting the in-app framing is faithful
(the two ceilings match; nothing is silently clipped), and the useful framing
range is roughly a 750-pixel-wide crop, not the desktop.

What today's code does is inherit: `PiPWatchViewport(transform:)` takes the
centre and zoom of what was on screen. That is a good default and a bad only
option — it fails exactly when the user is zoomed out, which is the state they
are in when they are *about to* leave the app.

## Requirements

- **FR-001 Tap enters with the current view.** Unchanged behaviour, now a
  stated contract rather than an implementation detail: one tap, no dialogue,
  framed on what the user was looking at.
- **FR-002 Long-press opens framing.** The PiP control's long-press presents
  the framing choices. The short press must never present anything — the whole
  point of spec 033 was that PiP is one tap.
- **FR-003 Three framing modes**, of which the founder asked for the second by
  name: **Current view** (default), **Follow activity** (automatic), and
  **Chosen region** (a region the user drew).
- **FR-004 Follow activity frames on what is changing**, derived from the
  damage rectangles the RFB layer already decodes per frame — no new
  instrumentation, and nothing sent to the remote. Its numeric contract:
  - the crop centres on the **area-weighted centroid** of recent damage;
  - crop width is the damage bounding box plus a margin, clamped to a legible
    band (see Non-Goals for what happens when the box is wider than the band);
  - a **dead zone** suppresses re-framing until the target moves far enough to
    matter, and a **cooldown** bounds how often the window can move, because a
    PiP window that re-frames on every terminal line is worse than a fixed one;
  - **idle holds the last framing** rather than drifting or zooming out.
- **FR-005 The chosen region is drawn on the remote screen**, initialised to
  the current view, and confirmed explicitly. It is session-scoped: it names a
  place on a particular desktop layout, and persisting it across relaunches
  would restore a frame around whatever now happens to be there.
- **FR-006 The mode persists; the region does not.** The mode is a user
  preference (`AppSettings`); the region is a session fact.
- **FR-007 Constitution §I and §IV.** Framing is a local viewport decision —
  no new RFB message, no remote input. Nothing about it reaches logs or the
  diagnostic export beyond the mode as a fixed label and counts.
- **FR-008 The automatic policy is a pure value type in Core** with unit tests
  over synthetic damage sequences, because it is a control loop and the
  failure the user would report ("the window keeps jumping") is a property of
  the loop, not of AVKit.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — auto-framing policy | centring, the legible clamp, the dead zone, the cooldown, idle hold, and that a re-frame is suppressed when the target has not moved | direct, synthetic damage sequences |
| `swift test` — settings round-trip | the mode persists and decodes to the default when absent | direct |
| iPhone simulator, fixture captures | the long-press sheet and the region picker | screenshot pass |
| iPhone simulator UITest | tap does not present anything; long-press does | direct |
| **Founder device, build 11** | **is the PiP window readable, and does Follow activity land on the terminal that is printing** | the judgement this spec exists for |

## Non-Goals

- Following the remote cursor. The server sends the cursor *shape*
  (`RFBServerCursor`), not its position — position is only known for pointer
  events we sent ourselves. It would need the helper.
- Framing two distant active regions at once. When the damage box is wider than
  the legible band the policy centres on the busiest area and lets the rest fall
  outside, rather than zooming out to something unreadable. A split view is a
  different feature.
- Making PiP interactive. It stays watch-only (constitution).
- Per-profile framing memory. FR-006 keeps the region session-scoped; a saved
  "watch this corner of that Mac" is a reasonable later feature and needs the
  profile model.

## Residual Risk
- The legible band is derived from arithmetic (3024 ÷ 4 ≈ 756 px ≈ 80 columns),
  not from a measurement of a real PiP window, which cannot be captured on a
  simulator because PiP is unsupported there (spec 032). The founder's device
  is the only place the band can be checked, and if it is wrong the constants
  move.
- Damage rectangles describe what the *server chose to send*, not what the user
  would call activity. A screen with a clock in the corner has damage there
  every second; the dead zone and the area weighting are what keep that from
  winning, and neither is validated against a real desktop yet.
- A cooldown that feels right on a busy terminal may feel sluggish when the
  user switches windows on the Mac. One constant cannot be right for both;
  this ships with the busy-terminal case tuned, because that is the founder's
  workload.
