# Web research — multi-monitor Mac: giant framebuffer, degraded phone experience

Read-only web round, 2026-09-04, founder question: "멀티모니터 띄워둔 맥에 접근할 때
초대형 해상도가 오면서 해상도/비트레이트가 형편없이 떨어진다 — 어떻게 해소하나?"
Claims carry source URLs; nothing here is measured by us unless noted as repo-measured.

Prior rounds: `artifacts/research/2026-08-20-streaming-performance-levers.md`
(Apple codec / ScaleFactor / HP landscape — still valid; this round is the
multi-display slice of it).

---

## 1. Verdicts up front

| # | Candidate lever | Verdict from this round |
|---|-----------------|-------------------------|
| A | **Per-display TCP ports 5901/5902 on built-in Screen Sharing** | **Premise most likely wrong on modern macOS.** The 5900+N-per-display scheme is the generic RFB display-number convention honored by *third-party* VNC servers (Edovia files it under "Selecting a display on a PC"); Apple's own ARD doc that `specs/008/research.md` D2 cited is about controlling a machine "running non–Apple VNC software" (ARD glossary: *client computer* = the controlled machine). The BetterDisplay maintainer states built-in Screen Sharing/Remote Management does **not** serve per-display ports. One legacy (2009, Leopard-era) forum anecdote affirms it. The 10-second `nc -vz <mac> 5901 5902` probe on the founder's 3-display Mac still settles it locally, but expect CLOSED. |
| B | **Apple's real display machinery: `0x451` layout + `0x0d` SetDisplay** | Documented (reverse-engineered) but **inside the Apple-auth record layer** (security types 30/33/35/36). This is what Screens 5's Mac display selection uses ("a feature offered via Screen Sharing/Remote Management on macOS"). Server-side single-display streaming = full resolution, no wasted pixels — the ideal VNC-path answer, priced at implementing Apple auth (`specs/008`). |
| C | **`0x0d` on the plain VNC-password path** | **Unknown, cheap to probe.** iShareScreen claims no path from VNC auth into the display machinery — but the same doc's layering claim is already contradicted by our own live measurement that `0x08` ScaleFactor **is** honored on VNC-password auth (spec 018). A guarded probe (Apple-type-advertisement gate, same class as 018 FR-001) with candidate display IDs would settle it. Without `0x451` we have no CGDirectDisplayIDs on that path; candidates are small integers (0/1/2) and the `0xffffffff`/`0` sentinels observed in `0x09`. |
| D | **Helper per-display capture (ScreenCaptureKit)** | Clean and available today: `SCShareableContent` → `SCDisplay` → `SCContentFilter(display:excludingApplications:exceptingWindows:)`. The helper can also *report* the true display layout to the phone, which removes `specs/014`'s biggest setup cost (Apple announces nothing readable on the VNC-password path — repo-measured, ExtendedDesktopSize rects = 0). |
| E | **Client-side focus (`specs/014` draft)** | Remains the no-cooperation fallback **and** the UX layer for every transport. Every commercial client we looked at does (B), (D), or (E); nobody gets per-display streaming out of built-in macOS over plain VNC. |

Interaction with what already shipped: spec 018 (ScaleFactor 0.5) cuts the
zoomed-out union frame 4× (repo-measured) but does not make three desktops
readable — that is 014's job; zoomed into one display the ladder restores 1.0
and the union cost returns, which is exactly the gap (B)/(C)/(D) close.

---

## 2. Per-question findings

### Q1 — Do the per-display ports exist on modern macOS?

- **Apple ARD guide, "View a VNC server's additional displays"**
  ([support.apple.com](https://support.apple.com/guide/remote-desktop/view-a-vnc-servers-additional-displays-apd5fcc5d03/mac)):
  "To control the second and third displays, you can set the screen sharing
  port to 5901 and 5902" — but the context is a computer **running non-Apple
  VNC software**, i.e. a third-party server that follows the RFB
  port-5900+display-number convention; "display designations start at 0 for
  the default primary display". **This is a premise correction for
  `specs/008/research.md` D2**, which read it as Apple's screensharingd
  serving 5901/5902. (Doc footer © 2026; internal links reference ARD 3.10 /
  macOS 13.6.)
- **Edovia, Screens 5 "Display Selection"**
  ([help.edovia.com](https://help.edovia.com/en/screens-5/features/display-selection/)):
  the port text lives under **"Selecting a display on a PC"** — "If you have
  three displays, you may use ports 5901, 5902, or 5903 to specify Display 1,
  2, or 3… Note: this feature may not be supported by the VNC server
  installed on your PC." For Macs, Screens instead uses on-the-fly selection
  offered by Screen Sharing/Remote Management (⇧⌃0 = all, ⇧⌃1/2/3 = display N,
  remembered per connection).
- **BetterDisplay discussion #1805**
  ([github.com/waydabber](https://github.com/waydabber/BetterDisplay/discussions/1805),
  2023-05 → 2024-10): maintainer waydabber — with macOS built-in Screen
  Sharing/Remote Management "you don't use separate ports"; per-display ports
  require running a custom VNC server bound per screen. The original user
  ended up using display selection instead.
- **MacRumors 2009 (Leopard era)**
  ([forums.macrumors.com](https://forums.macrumors.com/threads/vnc-and-dual-screens.693672/)):
  "main screen will generally be on port 5900 and the second screen on 5901"
  with a third-party client — oldest affirmative anecdote; no modern
  confirmation found.
- **Modern coexistence note:** High Performance screen sharing uses **UDP**
  5900–5902 ([Apple](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac)),
  which does not by itself occupy TCP 5901/5902 but shows Apple's own use of
  the number space.

Net: no source from the Sonoma/Sequoia/Tahoe era confirms TCP per-display
serving by screensharingd, one informed maintainer denies it, and the two
vendor docs that mention the scheme scope it to third-party servers. Keep the
one-line `nc` probe as the formal closure, at expected-fail.

### Q2 — What does Apple's protocol actually offer for multi-display?

From the reverse-engineered spec
[iShareScreen `apple_vnc_rfc.md`](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md):

- **`0x451` AppleDisplayLayout** (server→client, FBU rectangle): u16 version
  (observed 5), leader with `current_display` (u32, `0xffffffff` = none) and
  flags, then n × 56-byte display records carrying **CGDirectDisplayID**,
  global bounds, scaled bounds (HiDPI: backing = 2 × scaled), main-display
  and mirror-set bits, and a per-display `scale_factor` (f64). Clients must
  treat layout updates as authoritative for framebuffer sizing.
- **`0x0d` SetDisplayMessage** (client→server, 8 bytes):
  `u8 0x0d || u8 combine_all_displays || u16 reserved || u32 display_id`;
  observed body `0d 01 0000 00000000` selects the combined aggregate; a
  nonzero combine flag makes `display_id` ignored — i.e. `combine=0` +
  a display_id from `0x451` is the single-display lever.
- **`0x09` AutoFrameBufferUpdate** carries a `u32 selected_screen`
  (0 = first, `0xffffffff` = all/main).
- **`0x1d` SetDisplayConfiguration** — per-display mode table; render
  resolution vs logical size; per-display dynamic resize via
  `display_flags` bit 0x01. (The lever a native client would use to
  right-size a display; ours would be ScaleFactor/helper, not this.)
- **Auth boundary:** the doc states the display machinery lives inside the
  AES-128-CBC record layer that only exists after an Apple auth branch
  (30/33/35/36), with no path from plain VNC auth. **Repo counter-evidence:**
  `0x08` ScaleFactor was live-measured as honored on plain VNC-password auth
  (spec 018), so the layering claim is not absolute and `0x0d` is a fair
  probe subject — with the same non-Apple-server desync danger 018 FR-001
  already gates against (RFB has no client-message length negotiation).

### Q3 — What do commercial clients do on multi-monitor Macs?

- **Screens 5**: on-the-fly display selection on Macs via the Apple path;
  port-per-display only as a PC/server convention
  ([Edovia](https://help.edovia.com/en/screens-5/features/display-selection/)).
- **Jump Desktop**: per-display switching from the toolbar
  ([support article](https://support.jumpdesktop.com/hc/en-us/articles/360037987092));
  its high-performance lane is the separate Fluid agent, same architecture
  lesson as NaruHelper.
- **RealVNC Connect**: per-monitor viewer windows where the platform allows
  ([help](https://help.realvnc.com/hc/en-us/articles/360006483577-Working-with-multiple-monitors-in-RealVNC-Connect)),
  and an own-agent **virtual displays** feature that adds displays at chosen
  resolutions ([help](https://help.realvnc.com/hc/en-us/articles/31739688741405-Adding-Virtual-Displays))
  — the commercial precedent for "make the framebuffer phone-sized instead of
  shrinking a 9K union".

Pattern: speak Apple's protocol (auth-gated), run your own agent, or crop
client-side. No third party gets per-display streaming from built-in macOS
over plain VNC.

### Q4 — Helper per-display capture

- ScreenCaptureKit captures a chosen display:
  `SCShareableContent` → `SCDisplay` →
  `SCContentFilter(display:excludingApplications:exceptingWindows:)` →
  `SCStream` ([Apple sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)).
  Permission is the Screen Recording grant NaruHelper already asks for
  (spec 007/010).
- Gotcha worth remembering: captured dimensions come back in points vs
  backing pixels depending on filter/configuration
  ([SO](https://stackoverflow.com/questions/78847211/how-to-capture-screenshot-at-screen-resolution-with-screencapturekit),
  [Terzi](https://federicoterzi.com/blog/screencapturekit-failing-to-capture-the-entire-display/));
  a full-resolution single display is the point of this path, so pin backing
  size explicitly.
- The same `SCShareableContent` list is the display-layout report that
  `specs/014` US-2 scenario 5 wants (layout `source: helper`).

### Q5 — Virtual displays (secondary, future-note only)

- Apple's own endgame for "the framebuffer should match the client" is the
  High Performance **virtual display + Dynamic resolution** (window-size
  matching), native clients only, Apple silicon both ends, UDP 5900–5902
  ([Apple](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac),
  [Mac Help](https://support.apple.com/en-kg/guide/mac-help/mh14066/mac)).
- RealVNC does the same idea with its own agent (Q3). Creating virtual
  displays programmatically on macOS today means private-API territory
  (BetterDisplay class of tooling) — **not** a v1 NaruHelper lever; recorded
  so nobody re-researches it from zero.

---

## 3. Ranked actions for the founder's scenario

1. **(probe, minutes)** On the founder's 3-display Mac: `nc -vz <mac> 5901
   5902`, and if open, an RFB connect to see what framebuffer it serves.
   Expected closed (Q1) — the value is converting "expected" into measured.
2. **(probe, small)** `0x0d` SetDisplay on the plain VNC-password path behind
   the 018-style Apple gate, candidate display_ids 0/1/2 + sentinels, verdict
   = framebuffer extent change via DesktopSize. This is the highest
   information-per-effort item in this round: if honored, single-display
   streaming arrives without Apple auth and rewrites `specs/014`'s VNC-path
   design.
3. **(already built)** Spec 018 founder device pass — the zoomed-out union is
   already 4× cheaper; sharpness/zoom round-trip is the residual.
4. **(spec exists)** `specs/014` planning — client-side focus is the UX floor
   for every transport; helper-reported layout kills the manual-setup cost.
5. **(structural)** Helper per-display capture (Q4) — full-res single display
   at phone-chosen bitrate; pairs with 020/021 caps and codecs.
6. **(large, last)** Apple auth completion (`specs/008`) — unlocks `0x451` +
   `0x0d` + Apple codecs (+ HP later) on the no-helper path. iShareScreen is
   the reference; it is the "real Screens-class" answer and a real project.

---

## 4. Unknowns → measurements that would settle them

| Unknown | Settling measurement |
|---|---|
| Do TCP 5901/5902 serve single-display framebuffers on the founder's modern macOS? | `nc -vz` + one RFB handshake per open port (live probe). |
| Is `0x0d` honored on VNC-password auth? | Guarded live probe; success = DesktopSize extent collapse to one display's bounds. |
| What `display_id` values are valid without `0x451`? | Same probe, iterate 0/1/2 + `0xffffffff`; observe which (if any) select. |
| Does single-display selection change produce-rate (fewer damaged pixels → more content fps)? | Existing live benchmark (`scripts/run-naru-live-benchmark.sh`), 3-display Mac, before/after selection. |
| ScreenCaptureKit point-vs-backing size on the founder's displays | Helper-side `SCStream` configuration dump (one-off probe). |

---

## Self-verification (research round)

1. **Trap docs:** `NEXT_STEPS.md` P1 `specs/014` item (ports claim attributed
   to `specs/008/research.md:44`) — this round corrects the *reading* of that
   Apple doc (Q1); the `nc` probe recommendation stands, now at expected-fail.
   Constitution §V (no-helper path must work) respected: ranked actions keep
   client-side focus above Apple-auth-dependent work.
2. **New mappings:** none implemented; research only.
3. **Other surfaces:** compared Screens 5, Jump Desktop, RealVNC, BetterDisplay
   ecosystem, iShareScreen, Apple ARD/HP docs.
4. **Existing behavior removed:** none.
5. **User-facing copy:** none.
6. **Test assertions:** none.
7. **Spec conflicts:** `specs/008/research.md` D2 premise vs Q1 evidence —
   reported here, not silently edited (the spec file records its own round's
   reading; amendment belongs to that feature's process).
8. **Hot-path cost:** n/a.

**Deliberately not done:** no live probes from this round (research-only, no
Mac credentials in play); no iShareScreen code reviewed beyond its public
protocol doc; no changes to specs or code.

DONE-MULTIMONRESEARCH

---

# Lead addendum — live probes (2026-09-04, founder's imagoworks 3-display Mac)

Host: `imagoworks-hckim-3` (Tailscale 100.123.228.86, macOS, three displays,
VNC-password auth). Probe: `LiveMacDisplaySelectionTests` in
`FakeRFBServerKitTests` (env-gated), written this round alongside probe-only
wire vocabulary (`RFBClientMessageEncoder.appleSetDisplay` 0x0d;
`RFBNetworkClient.advertiseAppleDisplayLayoutEncoding` 0x451).

- **Ports (verdict A): measured CLOSED.** `nc -vz`: 5900 open;
  5901/5902/5903 Connection refused. The web reading — the 5900+N
  per-display convention belongs to third-party VNC servers, not
  screensharingd — is confirmed on this host; `specs/008/research.md` D2's
  premise stands corrected.
- **Served union: 10240 × 5114.** The multi-monitor frame the phone
  receives today.
- **`0x451` layout (Q2): NOT sent on the VNC-password path.** Encoding
  advertised mid-session via SetEncodings; 3 clean updates followed, no
  layout rectangle (and none undecodable). Display bounds cannot come from
  this wire.
- **`0x0d` SetDisplay (verdict C): probed, NOT honored.** Across ids 0–3 on
  two runs the framebuffer never resized (`didResizeDesktop=false`,
  DesktopSize rects = 0, 10240 × 5114 throughout). The first run's "extent
  ratio 1.01 × 0.56 → HONORED" was a probe artifact: a full update's damage
  extent is not the framebuffer size (baseline damage measured 5087 wide of
  a 10240-wide framebuffer). The classifier now requires a resize
  announcement before calling anything honored.
- **Caveat:** while the founder's own viewer session was active, extra
  probe connections were sometimes dropped (read-timeout / not-connected) —
  those "rejected" verdicts describe stream drops, not server answers
  about the id.
- **Net:** iShareScreen's auth boundary holds for the display machinery —
  `0x08` ScaleFactor (spec 018) remains the only Apple display lever on the
  VNC-password path. The ranked path collapses to: 018 founder device pass →
  `specs/014` client-side focus (bounds user-declared or helper-reported) →
  helper per-display capture → Apple auth (`specs/008`) for the real
  `0x451`/`0x0d`.

DONE-MULTIMONRESEARCH-PROBED
