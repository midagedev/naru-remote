# Feature Specification: Multi-Display Focus

**Feature Branch**: `014-multi-display-focus`
**Created**: 2026-08-19
**Status**: Draft — research measured (see *What The Wire Actually Carries*),
not yet planned. Blocking input: one probe run against the founder's
three-display Mac (see *Open Questions*).
**Product**: Naru Remote
**Input**: Founder device pass 2026-08-19 — "이번에 테스트 해보면서 멀티모니터
지원에 대해서 좀 해법이 필요하겠다고 느끼네 이거 한꺼번에 모니터 세개가
나오는군."

## Problem

A Mac with three attached displays is served as **one framebuffer covering all
of them**. On a phone the result is that the desktop the user actually wants
occupies roughly a third of an already small screen, and there is no way to ask
for less. Everything downstream inherits the problem:

- **Nothing is legible.** A 6.9" phone showing a ~9000 px wide union renders a
  terminal line at a few pixels of height.
- **Zooming in does not help navigate.** Once zoomed to a readable scale the
  user is panning blind across a canvas three desktops wide with no landmarks
  and no way to say "the middle one".
- **It made a working feature look broken.** The founder reported the same day
  that trackpad-mode hover "실제 화면에 호버이벤트를 트리거 하지 않는다", then
  found on re-test that the pointer does follow. The live probe
  (`LiveMacPointerHoverTests`) had already shown the protocol path to be sound —
  a buttonless `PointerEvent` moves the real pointer and the server repaints
  (1527 changed pixels). The most likely explanation for the initial reading is
  that at three-display scale a hover highlight is a couple of pixels tall.
- **The new zoom floor makes it worse, correctly.** Spec-adjacent work on
  2026-08-19 lowered the hero viewport's floor from fill to fit
  (`ViewportZoomBounds`), which is right for one display and, for three, means
  "zoom out until all three are visible" — the least useful view there is.

The founder's own scenario (memory: sustained AI-CLI work from a phone) is
single-display work on a multi-display machine. The product needs a way to say
**which display**.

## What The Wire Actually Carries (measured 2026-08-19)

Recorded here because it eliminates the obvious design and forces the one below.

| Question | Method | Result |
|---|---|---|
| Does macOS Screen Sharing serve the union of all displays? | `LiveMacDisplayLayoutTests.testServedFramebufferSpansEveryAttachedDisplay` | Yes — served framebuffer equals the pixel bounding box of the attached displays (measured on a 1-display Mac: 3024×1964; the founder's 3-display report is the multi-display instance) |
| Does it announce the screen layout? | `LiveMacDisplayLayoutTests.testWhetherTheServerAnnouncesItsScreenLayout` | **No.** ExtendedDesktopSize(-308) rectangles = 0 and DesktopSize(-223) = 0 across 3 updates, with both encodings advertised in `SetEncodings` (`RFBEncoding.encodingList()` lines 320-321) |
| Do we discard a layout when one does arrive? | Code read | Yes — `RFBFramebufferDecoder.consumeExtendedDesktopSizePayload` (`:412`) reads the screen count and `skip`s the per-screen array |
| Can we request only part of the framebuffer? | Code read | Yes — `framebufferUpdateRequest(serverInit:incremental:region:)` (`RFBNetworkClient.swift:1076`) already encodes a sub-rectangle |

**Consequence**: display boundaries cannot be read from an Apple server. They
must come from somewhere else, and the design has to work when they come from
the user. Parsing -308 is still worth doing (TigerVNC/x11vnc do send it) but it
cannot be the mechanism this feature rests on.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Work On One Display (Priority: P1)

A founder connects from an iPhone to a Mac with three displays and wants the
middle one, full width, at a readable scale — the same experience as a
single-display Mac.

**Why this priority**: without it the product is unusable on the founder's own
machine, which is the ICP.

**Independent Test**: with a declared three-region layout, focusing region 2
makes the viewport's fit scale and pan bounds those of region 2 alone; the whole
union is no longer reachable by zooming out.

**Acceptance Scenarios**:

1. **Given** a session whose framebuffer is wider than any single declared
   region, **When** the user picks a display, **Then** the viewport fits *that
   region* to the screen — its fit scale, its zoom floor, its pan bounds.
2. **Given** a focused display, **When** the user zooms out fully, **Then** they
   see that display letterboxed, not the other two.
3. **Given** a focused display, **When** the user taps or types, **Then** input
   still lands at the correct point on the remote desktop — focus is a local
   view transform and changes no coordinate the server sees (constitution §I).
4. **Given** a single-display host, **When** the session opens, **Then** nothing
   about today's behavior changes and no display control is shown.

### User Story 2 — Tell Naru Where The Displays Are (Priority: P1)

Because no Apple server announces the layout, the user declares it once per host
and never again.

**Why this priority**: US-1 has no data without it.

**Independent Test**: a declared layout round-trips through the profile store,
is keyed to the framebuffer size it was declared against, and is ignored (not
misapplied) when the framebuffer size changes.

**Acceptance Scenarios**:

1. **Given** a connected session, **When** the user opens display setup and says
   how many displays there are, **Then** Naru proposes an equal-width split of
   the framebuffer as a starting point.
2. **Given** the proposal, **When** the user drags a boundary on a thumbnail of
   the full framebuffer, **Then** the regions update live and can be saved.
3. **Given** a saved layout, **When** the user reconnects to that host, **Then**
   the layout and the last focused display are restored without setup.
4. **Given** a saved layout and a framebuffer that no longer matches the size it
   was declared against (a display was unplugged, resolution changed), **When**
   the session opens, **Then** Naru falls back to the whole framebuffer and
   offers re-setup — it never applies stale boundaries silently.
5. **Given** a server that *does* announce a layout (ExtendedDesktopSize), or a
   host running Naru Helper, **When** the session opens, **Then** the announced
   regions are used and setup is skipped; a user-declared layout still wins over
   an announced one if the user has edited it.

### User Story 3 — Never Lose The Pointer (Priority: P2)

**Independent Test**: with region 2 focused, a pointer move whose target lies in
region 3 changes the focused region to 3.

**Acceptance Scenarios**:

1. **Given** a focused display and trackpad mode, **When** the remote pointer
   crosses into another declared region, **Then** the view follows to that
   region rather than leaving the pointer off-screen.
2. **Given** the view follows, **When** it does, **Then** the transition is a
   single animated move and the focused-display control reflects the new
   display.

### User Story 4 — Send Only The Pixels In Use (Priority: P3)

**Independent Test**: with a region focused, `FramebufferUpdateRequest` carries
that region's rectangle rather than the full framebuffer, and a live session
still repaints correctly after focus changes.

**Why this priority**: bandwidth and latency on cellular are the phone-first
payoff, but it is an optimization on top of a working US-1 and it touches the
protocol path, so it ships behind its own live gate.

**Acceptance Scenarios**:

1. **Given** a focused region, **When** the client requests an incremental
   update, **Then** the request rectangle is the focused region.
2. **Given** the user switches displays, **When** the next request goes out,
   **Then** it is non-incremental for the newly focused region (the client has
   no valid pixels for it yet) and the screen is correct within one update.
3. **Given** a server that ignores the request rectangle and sends the whole
   screen anyway, **When** that happens, **Then** the client still renders
   correctly — the optimization degrades, it does not break.

## Requirements *(mandatory)*

- **FR-001**: A display layout is an ordered list of non-overlapping regions in
  framebuffer pixel coordinates, each with a stable identifier and a
  user-visible label ("Display 1"…). The whole framebuffer is the one-region
  degenerate case and is the default.
- **FR-002**: A layout records its `source` (`announced`, `helper`, `userEdited`)
  and the framebuffer size it was declared against. A layout whose size does not
  match the live framebuffer must not be applied.
- **FR-003**: Focus is a **local view transform only**. No new RFB message, and
  no change to how pointer/key coordinates are computed (constitution §I).
- **FR-004**: `ViewportZoomBounds` computes fit/fill/floor against the focused
  region's rect rather than the framebuffer, preserving the 2026-08-19
  separation of opening scale (fill) from floor (fit).
- **FR-005**: The display control is shown only when a layout has more than one
  region; a single-display session's UI is unchanged.
- **FR-006**: Layouts persist per profile in the existing file-backed profile
  store. They contain geometry only — never screen contents, window titles, or
  host identity beyond what the profile already stores (constitution §IV).
- **FR-007**: The decoder retains the ExtendedDesktopSize screen array instead of
  skipping it, and surfaces it through the RFB boundary as an announced layout.
  Malformed or absurd arrays are rejected the way absurd `DesktopSize`
  dimensions already are (`RFBFramebufferDecoder.swift:27`).
- **FR-008**: Diagnostics report display-layout state through the fixed
  safe-detail catalog (region count and source only) — no coordinates that
  describe the user's physical desk arrangement beyond what is needed, and no
  caller-provided strings.

### Key Entities

- **`DisplayRegion`** — `id`, `rect` (framebuffer pixels), `label`.
- **`DisplayLayout`** — `regions`, `source`, `declaredForFramebufferSize`,
  `focusedRegionID`. Pure Core type; validation (non-overlap, in-bounds,
  non-empty) lives with it.
- **`DisplayLayoutStore`** — persistence on `ConnectionProfile`, same boundary
  rules as the rest of the profile store (no credentials, no content).

## Verification Matrix

| Claim | Method | Surface | Command |
|---|---|---|---|
| Region validation, equal-split proposal, size-mismatch rejection | XCTest | Core | `swift test --filter DisplayLayoutTests` |
| Fit/floor/pan computed against the focused region | XCTest | Core | `swift test --filter ViewportZoomBoundsTests` |
| Focus changes no server-facing coordinate | XCTest | Core | `swift test --filter PointerCoordinateMappingTests` |
| Announced layout parsed from -308 (fixture) | XCTest + `FakeRFBServer` fixture | Core | `swift test --filter RFBFramebufferDecoderTests` |
| Layout round-trips and survives reconnect | XCTest | Core | `swift test --filter ConnectionProfileStoreTests` |
| Display setup and switching read correctly on a phone | XCUITest screenshot | **iPhone first** (§VI) | `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test` |
| Same at regular width | XCUITest screenshot | iPad | as above with the iPad destination |
| Sub-rect requests work against a real server | Live probe | Real Mac | `swift test --filter LiveMacDisplayLayoutTests` |
| **Residual** | Physical device | iPhone + the founder's 3-display Mac | fold into the paired-device pass |

## Open Questions

1. **Does the founder's three-display Mac announce a layout?** This Mac has one
   display, and a server can behave differently with several. Run, with the env
   pointed at that host:
   `swift test --filter LiveMacDisplayLayoutTests`
   If ExtendedDesktopSize rectangles > 0 there, US-2's manual setup becomes a
   fallback rather than the main path, and US-1 can ship without it.
2. **Do the per-display ports exist?** `specs/008` research claims Apple serves
   additional displays on TCP `5901`/`5902` (`research.md:34`, `:44`), which was
   never verified against a modern macOS. If true it is a better US-1 than
   cropping — full resolution, a third of the bandwidth, no layout needed. Check
   is one line from the founder's network: `nc -vz <mac> 5901 5902`.
3. **Which display is focused on first connect?** Last used is the obvious
   answer; the first session on a new host has no last-used and no cursor
   information, so it defaults to region 1 unless (2) gives us something better.

## Residuals

- Boundary detection from pixel content (never-changing black filler bands
  between displays of unequal height) would remove most of the manual setup but
  yields nothing for three identical monitors in a row. Deliberately out of
  scope for the first pass; revisit only if manual setup proves annoying in use.
