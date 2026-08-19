# Feature Specification: Quiet Ops Visual Refinement

**Feature Branch**: `016-quiet-ops-visual-refinement`
**Created**: 2026-08-19
**Status**: Implemented 2026-08-19 (round 1: host list + session chrome + mode pill). Founder device pass residual.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-19 — "전반 UI도 좀 개선하고 싶은데 호스트 목록 화면이나
컨트롤 화면의 버튼들이나 이런것들이 너무 미려하지 않아."

## Problem

The screens work but read as unstyled defaults, not as BRANDING.md §6.1's
"Quiet Ops Console". Audited on iPhone 17 Pro (light), 2026-08-19:

1. **Host list card** stacks four caption rows (endpoint, host-kind, helper
   readiness, status) like a debug listing; the `…` actions button is a 44pt
   translucent-material circle floating over the preview (the same
   unpredictable-background class BRANDING.md §7 bans for remote-screen
   chrome); the card is a sharp 8pt-radius box with no elevation.
2. **Header** `+` renders as a gray capsule — the screen's one primary action
   carries no Signal Blue (usage rule: "Blue는 사용자가 누를 수 있는 주요 행동").
3. **Session immersive bar**: Disconnect is `bolt.horizontal.circle.fill`
   tinted system red — at icon size it reads as a messenger logo, not as
   "sever the lane"; the three trailing buttons carry three different visual
   weights.
4. **Floating mode pill**: Compose's `text.cursor` glyph renders as a
   localized letterform ("가|") on Korean devices — the same defect fixed for
   the dock's mode toggle in spec 015, still live here.

## Requirements

- **FR-001**: A nominal host card MUST present at most three text rows below
  the preview: name+status, mono endpoint, one tag row (host kind + helper
  readiness as compact capsule tags). Warnings/failures/connecting states may
  add their row as today.
- **FR-002**: Status MUST be carried by a colored dot beside neutral-ink text
  (quiet capsule), never by colored text alone — status hue needs only the
  3:1 non-text contrast, and the text keeps AA on its surface.
- **FR-003**: Cards use radius 12, the Hairline stroke, and a subtle elevation
  shadow; the actions `…` button is an opaque `surfaceKey` square (radius 8,
  hairline, ~34pt visual inside the existing 44pt hit area) — no translucent
  material over preview pixels.
- **FR-004**: The host list header's `+` is Signal Blue filled (the screen's
  single prominent action).
- **FR-005**: Session bar buttons share one visual weight (equal icon frames);
  Disconnect uses `bolt.slash.fill` tinted with the Coral *token* (not system
  red).
- **FR-006**: No mode glyph anywhere may render as a localized letterform:
  the floating pill's Compose uses `square.and.pencil` (matches the dock's
  spec 015 toggle).
- **FR-007**: Every accessibility identifier on these surfaces is unchanged —
  the existing UI suites are the regression net for behavior; this spec is
  visual only.
- **FR-008**: Any new (text, background) pair joins `NaruColorContrastTests`.

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — `NaruColorContrastTests` | new pairs hold WCAG AA in both themes |
| XCUITest — existing grid/session/store suites | identifiers + behavior unchanged (FR-007) |
| UX audit re-captures (iPhone light/dark) + lead vision pass | the four audit findings are visually closed |
| Founder device pass (residual) | the felt result |

## Residual Risk

- "미려함" is taste; this round closes the audited defects (defaults, mixed
  weights, letterform glyph, material-over-pixels). Further passes (profile
  editor form, empty states, dark-theme sweep) are follow-on rounds — the
  founder's reaction to round 1 steers them.
