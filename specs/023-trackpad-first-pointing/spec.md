# Feature Specification: Trackpad-First Pointing

**Feature Branch**: `023-trackpad-first-pointing`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21 (trackpad default + cursor centering,
vertical breathing band, glyph hotspot single owner; `swift test` 1705/0
failures, live simulator gate green with FAIL-first counterparts for the band
and the hotspot). Founder device pass pending.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-21 — "이거 트랙패드 모드를 기본 입력모드로
하고 이거 줌인 모드에서도 상하에 여백공간이 좀 나와야 아래쪽 끝을 가기 쉽다.
그리고 이거 미세하게 트랙패드 커서 끝이랑 실제 클릭되는곳 갭이 있는것 같아
이것도 확인해야해".

## Why

Three findings from device use, all in the same gesture loop — point, reach,
click:

1. **Direct touch is the wrong default for a phone.** `PointerControlMode
   .productDefault` has been `.directTouch` since spec 003, where trackpad was
   introduced as the precision affordance "one tap away in the control bar".
   The founder's own workflow (sustained AI-CLI/GUI sessions from an iPhone) is
   precision work on a small screen — a fat-finger absolute tap is the
   exception, not the baseline. Chrome Remote Desktop ships trackpad as the
   default for the same reason.

2. **The bottom of the remote screen is hard to reach while zoomed.**
   `ViewportTransform.clampPan` keeps content edges flush with the view edges,
   so the last rows of the remote screen can only ever rest at the very bottom
   of the viewport — which on a live session is exactly where the floating
   input dock sits (`NaruRemoteAppShell` `.overlay(alignment: .bottom)` when
   `usesFloatingOverlay` is true). And in trackpad mode there is no one-finger
   pan to work around it: moving the view is auto-pan only
   (`TwoFingerGestureIntent` — two fingers are always the remote scroll
   wheel), and auto-pan stops where the clamp stops. The remote Dock / menu
   extras end up under app chrome with no way to lift them out.

3. **The trackpad cursor's tip does not point at the click.** Both render
   paths place the *centre* of the fallback `cursorarrow` glyph at the cursor's
   framebuffer position: `MetalFramebufferView.updateHotCursorOverlay`
   (`hotCursorView.center = anchor`) and `SessionViewportView
   .syntheticCursorOverlay` (`.position(point)`). The SF Symbol's arrow tip is
   near the *top-left* of its box, so the tip draws up-and-left of the point
   that is actually clicked. Measured on the same SF Symbol artwork at the
   shipping 22pt configuration: the rendered box is 19×26pt and the tip pixel
   sits at (3, 3) — **6.5pt left and 10pt above the image centre**, an ~12pt
   diagonal lie on a phone. The Metal path compounds it by forcing the box to
   22×22 with `contentMode = .scaleToFill`, which both distorts the glyph and
   moves the tip again.

   The server-cursor path is already correct — it offsets by
   `hotSpotX`/`hotSpotY` — so the defect only shows when no RFB cursor shape
   has arrived, which is the common case for the fallback glyph.

## Requirements

- **FR-001** `PointerControlMode.productDefault` is `.trackpad`. Every fresh
  session, disconnect, and profile change resets to it (existing
  `resetPointerControl()` path); the control bar toggle still reaches
  `.directTouch` and the direct-touch behaviour is otherwise unchanged.
- **FR-002** When trackpad mode is active and the remote coordinate space
  becomes known (fresh connect, or a DesktopSize resize that arrives before the
  user has moved anything), the cursor is centred and visible. A cursor that
  the user has already placed is never teleported by a later size update.
- **FR-003** While an axis is actually overflowing the viewport (i.e. zoomed
  far enough that local pan is possible), the vertical pan clamp allows extra
  travel beyond flush — a top/bottom breathing band — so the first and last
  rows of the remote screen can be parked clear of the app's top action bar and
  bottom input dock. The band is sized to the auto-pan follow margin
  (`PointerGestureResolver.followPanMargin`, ≤96pt) so a cursor pushed to the
  bottom comes to rest on the follow line with the remote screen's bottom row
  above the dock.
- **FR-004** Horizontal clamping stays flush (the founder asked for 상하 only),
  and at fit scale (no overflow) pan stays locked at zero — the band must never
  let the fitted image drift inside its letterbox.
- **FR-005** The band is not a rubber band: pan parked inside it stays there
  until the user pans back or resets the zoom. Parking the bottom row above the
  dock is the point of the feature.
- **FR-006** The fallback cursor glyph's **tip** lands on the cursor's
  framebuffer position in both render paths, within 1pt. The tip's location
  inside the glyph is *derived from the rendered glyph* (alpha scan: topmost
  opaque row, leftmost opaque pixel in it), not from a hand-written constant,
  so new SF Symbol artwork cannot silently re-introduce the offset.
- **FR-007** The glyph is drawn at its natural aspect ratio — no
  `scaleToFill` into a square box.
- **FR-008** Single owner: one type owns the glyph (symbol name, point size,
  rendered image, tip offset) and both the Metal hot path and the SwiftUI
  fallback consume it. Neither path may re-derive placement locally.
- **FR-009** Constitution §IV: no cursor coordinate, framebuffer dimension, or
  pan offset is logged, exported, or persisted by any of this.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — `PointerControlTests` | `productDefault == .trackpad` | pinned contract |
| `swift test` — `ViewportTransformTests` | band appears only on an overflowing axis; horizontal stays flush; fit scale stays locked; band is reachable by `panToReveal` | FAIL-first against the old clamp |
| `swift test` — `TrackpadCursorGlyphTests` | tip-point scan (synthetic bitmap) and centre-placement math | pure, no simulator |
| `swift test` — `TrackpadModeModelTests` | cursor centred + visible when the coordinate space arrives in trackpad mode; an already-placed cursor is not teleported | app-model level |
| iPhone 17 Pro simulator, live Mac | trackpad is live on connect without a toggle; the bottom row can be parked above the dock; the drawn tip sits on the clicked pixel | screenshot + vision judgement |
| Founder device (iPhone) | the felt gap is gone; reaching the remote Dock while zoomed | device pass |

## Residual Risk

- The breathing band's size is a policy constant tied to the follow margin. If
  a future dock layout grows past 96pt the bottom row is again reachable only
  under chrome; the band would need to become inset-driven.
- The tip offset is derived at runtime from the rendered symbol. If a future
  iOS ships `cursorarrow` artwork whose tip is *not* in its topmost opaque row
  (e.g. a right-pointing variant), the scan would pick the wrong pixel. The
  pure scan test documents the assumption.
