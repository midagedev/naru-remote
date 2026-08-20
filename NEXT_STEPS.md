# Next Steps

Updated: 2026-08-20 KST.

Cross-feature priority queue for any coding agent (Claude Code, Codex) and
the founder. Per-feature ground truth stays in each `specs/<n>-<slug>/spec.md`
**Status** line and `tasks.md`; this file only orders the work across
features. When you finish or reprioritize an item, update this file in the
same PR.

## Now — ship blockers (P0)

1. **`specs/011` physical-device pass** — the simplified input UX is
   implemented, `swift test` green (1522 tests), and the live-Mac E2E is
   **verified end-to-end** (2026-08-17: Type "Naru"/"한글" and Compose
   `NARUSIM_한글_END` all arrived exactly on the real Mac; resolution log in
   `specs/011-simplified-input-ux/spec.md`). Remaining: the founder's paired
   physical iPhone pass (Korean IME through Type mode, accessory strip with
   sticky modifiers, click feel, Bluetooth keyboard).
1a. **`specs/012` external pointer & strip completions** —
   **implemented 2026-08-18**: BT mouse/trackpad scroll wheel, secondary
   click, system-pointer hide + hover in both modes, strip hold-repeat,
   one-tap ⌃C, IME-flush barrier, iPad 720 pt dock cap, and an
   iPhone-width strip that fits Esc/Tab/⌃C. Unit + simulator gates green
   (`swift test` 1550). Remaining: the 13-item physical-device checklist
   in `specs/012-external-pointer-and-strip-completions/spec.md`
   (real mouse/trackpad/Pencil on iPad, hold-repeat feel and Korean IME
   flush on iPhone) — fold it into the paired device pass in item 1.
1b. **`specs/013` three-screen consolidation** — **implemented 2026-08-18**
   (`35c692d0`), **extended 2026-08-19 (US-4)** after the founder's device pass
   found the *connecting* state still reading as a third screen: tapping a card
   opened an empty remote-control screen (a "Waiting for first frame"
   placeholder under a full-height pinned dock). Connecting now belongs to the
   host list — the tapped card shows progress and Cancel, and remote control
   opens on the first frame. Both occurrences came from the same shape, a
   view-local route flag set on tap and corrected afterwards; that flag is gone
   and `RemoteControlSurfacePolicy` (Core) derives the surface from
   `(sessionState, hasFramebuffer)`. Remaining: a real failed connect, a real
   connect, and a real mid-session drop on device.
1c. **`specs/015` single-row input dock** — **implemented 2026-08-19** after the
   founder asked whether the keyboard-up dock was compact enough. It was not:
   measured six rows and **368pt above the keyboard on iPhone 17 Pro — 42% of
   the screen** (Type mode; Compose 349pt). With a software keyboard up that
   left the remote screen ~24%. Now one row (`⋯` · field · mode · Send), span
   40pt in Type and 88pt in Compose; modifiers, Esc/Tab/⌃C/arrows/Del, Fn,
   remote ⌫/↵ and the Mac window controls sit behind `⋯` (model-owned so a
   placement swap cannot collapse it, collapsed per session); the three status
   surfaces collapsed into one line that speaks only when the transport is
   degraded or a delivery failed, and the "Ready to compose locally"
   placeholder is gone. Gate: `KeyboardUpDockHeightUITests` measures **rows**
   (bands of vertically overlapping elements) from an identifier list of every
   dock row, so a new row cannot be silently excluded. **v1.1 (same day)**,
   from the founder's build-3 device pass: Compose field is one line (40pt,
   scrolls), Compose Send submits with a trailing Return (real Return keypress
   on the keystroke default), and Type mode dropped the text field entirely —
   its row is the soft-key strip (remote ⌫/↵ leading, keyboard-dismiss key,
   mode switch) over a 1×1 hidden first responder that keeps the IME boundary.
   Remaining: the founder's device pass on v1.1 with a real software keyboard,
   which the simulator (hardware keyboard attached) cannot show.
1d. **`specs/016` quiet-ops visual refinement** — round 1 implemented
   2026-08-19 after the founder called the host-list and session buttons
   "미려하지 않아". Host cards: status dot-capsule + one tag row + radius
   12/elevation + opaque `…` (no material over preview pixels); header `+` is
   Signal Blue; session bar buttons share one icon weight and Disconnect is
   `bolt.slash.fill` in the Coral token (the red `bolt.horizontal.circle`
   read as a messenger logo); the floating pill's Compose glyph no longer
   renders as "가|". Light Coral darkened `#E85D4F`→`#E2523F` (contrast gate
   caught 2.98:1 on Surface Muted). Identifiers unchanged. **Round 2
   implemented 2026-08-20** (founder: "계속해서 개선해서 출시품질 가자"):
   status-token sweep — no user-facing chrome colors status with raw system
   `.green/.red/.orange/.blue` anymore (diagnostics rows, session quality
   chip/status icon, reconnect badge, profile list; selection marks are
   Signal Blue, not green); the profile editor's host fields got URL
   keyboard / no autocorrect / no autocap (a hostname field opening on the
   Korean IME page was a functional defect); diagnostics stage codes went
   tertiary. Empty home + dark structure audited SHIP as-is. Remaining:
   founder device pass.
1e. **`specs/017` zoom-scoped streaming** — implemented 2026-08-19 after the
   founder asked whether VNC can stream only part of the screen. It can
   (RFC 6143 region requests) and the mechanism existed since spec 004
   FR-017, but D106 had gated it to the opt-in RGB565 profiles — the default
   profile requested full-framebuffer damage even zoomed in. Now every
   profile scopes zoomed *incremental* requests to the visible viewport
   (+64px margin, full-request heartbeat every 10th, region dropped when it
   saves <10% — so un-zoomed sessions are byte-identical to before); power
   saver still forces full; the initial request stays full outside the
   RGB565 lanes. Live-measured on this Mac's Screen Sharing with the default
   encoding: 5/5 region requests delivered, stream healthy after.
   **Ground-truth correction 2026-08-20**: a busy-screen rerun delivered 158
   out-of-region rects from the same server — Apple does NOT reliably clip
   to the region under load, so savings against Apple servers are
   workload-dependent (correctness unaffected; RFC-clipping servers still
   save; the live gate now prints in-region/straddling/fully-outside counts
   per run instead of asserting one day's workload). Remaining: the
   founder's cellular device pass, and if pan-reveal staleness is felt, a
   transform-change full-request hook.
1f. **Streaming performance levers — researched, not yet specified**
   (2026-08-20, `artifacts/research/2026-08-20-streaming-performance-levers.md`,
   web-research round; claims carry source URLs, unmeasured by us unless
   noted). Top candidates by impact/effort: ① wire helper
   `requestKeyframe`/stall recovery + VideoToolbox low-latency properties
   (S); ② helper adaptive bitrate + cellular caps via
   `NWPath.isExpensive`/Low Power Mode (S–M); ③ Apple `ScaleFactor 0x08`
   message (what Screens 5 sells as "Compression": server-side 0.5×
   downscale — the one cheap lever that works *against Apple's server*;
   **probe PASSED 2026-08-20** on the plain VNC-password path: honored at
   exactly 0.50×, the resize rides the standard DesktopSize path our
   decoder already handles, in-session restore works — promoted to
   `specs/018-adaptive-server-downscale`); ④ HEVC on the
   helper lane. Premise corrections recorded: Apple Screen Sharing has
   private still-image codecs (0x3e8–0x3f3) + a server-push message (0x09)
   + a reverse-engineered High-Performance HEVC path (iShareScreen, 2026) —
   "no third-party path" from the 2026-07-05 analysis is stale. Each lever
   needs its own spec + FAIL-first live probe before implementation.
1g. **`specs/019` helper video keyframe recovery — implemented 2026-08-20**
   (2026-08-20, lever ① from 1f). The requestKeyframe wire vocabulary from
   spec 007 was never wired: the helper advertises
   `supportsKeyframeRequest: true` but never reads inbound frames after
   startStream, and the app falls back to VNC on the first decoder-rejected
   access unit. Spec 019 wires both ends: helper-side per-stream force
   signal into the VT encode loop + authenticated inbound receive loop;
   app-side pure recovery policy (2 attempts, 30-AU budget) before VNC
   fallback. VT low-latency properties turned out already present on the
   live SCK path (EnableLowLatencyRateControl + RealTime), so the lever's
   VT half was verification, not new work. `streamStalled` stays terminal.
1h. **`specs/020` network-constrained stream caps — implemented 2026-08-20**
   (2026-08-20, lever ② from 1f, rescoped after code-read). "Adaptive
   bitrate + cellular caps" resolves to: respect **Low Data Mode**
   (`NWPath.isConstrained`) on both lanes — helper video caps to 15 fps
   (readability is already the only production quality), VNC joins the
   existing powerSaver/LowPower saver pairing. `isExpensive` deliberately
   changes nothing (constitution §VI: cellular is the baseline scenario,
   not an exception — pinned by test). Mid-stream helper bitrate changes
   need new wire vocabulary (schema v2) and path flips tear TCP anyway, so
   caps apply at stream (re)start like Low Power Mode today.
1i. **`specs/021` helper video HEVC — implemented 2026-08-20** (2026-08-20,
   lever ④ from 1f, the last researched lever; founder: "마지막까지 하고
   테스트하려고"). Offer/answer negotiation with zero extra round trips
   (optional `acceptsHEVC` on the start request; the `codec` field keeps
   carrying h264 so legacy decoders never see an unknown enum value;
   descriptor answers hevc iff offer × helper encode probe), HEVC encode
   (Main profile, low-latency) + HEVC render (VPS/SPS/PPS,
   `CMVideoFormatDescriptionCreateFromHEVCParameterSets`), bitrate rows at
   2/3 of H.264 marked provisional pending the device pass. After commit:
   TestFlight build for the founder's device passes across specs 015–021.
2. **`specs/007` real-screen helper-video + sustained-device gate** — run
   `bash scripts/run-naru-live-benchmark.sh helper-dev-app-setup` on the Mac,
   approve Screen Recording, then re-run
   `physical-iphone-helper-video-gate`. The synthetic-source physical gate
   passed 2026-07-05, and the 2026-07-12 release review bounded encoded H.264
   access-unit queues with fail-safe VNC fallback; neither substitutes for a
   30-minute real-screen RSS/thermal run.
3. **`specs/009` physical gates T021–T024** (`specs/009-live-type-through/tasks.md`):
   200-char Korean/English/number/symbol integrity ×10, per-commit latency
   p95, Unicode-KeyEvent no-input regression, and 30-min sustained live
   session. Requires the paired physical iPhone and the
   founder's Mac; VNC/helper credentials go through environment variables
   only — never into source, docs, or shell history.
4. **30-minute whole-product iPhone pass** — helper video, VNC fallback,
   Type/Compose, trackpad/zoom, reconnect, and PiP enter/leave in one
   session. Record only privacy-safe aggregate diagnostics and thermal/RSS
   verdicts (`SUBMISSION_READINESS.md` §5.4).
5. **App Store Connect human steps** (`SUBMISSION_READINESS.md` §5.5) — app
   record, hosted privacy policy URL, TestFlight distribution, EU DSA trader
   and Korea declarations, then submit. Founder decision D3 (Live→default) is
   EXECUTED by spec 011 + the constitution §I amendment (2026-08-17).
   **Screenshots are shot** (2026-08-18): five dedicated store states for the
   6.9" iPhone and 13" iPad slots, light and dark. The curated upload set —
   five iPhone, four iPad, all dark — is
   `artifacts/app-store/20260819-build2/`; raw captures stay local in
   `artifacts/screenshots/store/`. Procedure and framing rationale:
   `docs/store-screenshots.md`. The light captures predate the 2026-08-19 dock
   contrast fix; the light iPhone slots 2 and 3 have been re-shot, the rest
   would need re-shooting before a light set could be uploaded.

## Near term (P1)

- **`specs/014` multi-display focus** — the founder's Mac has three displays and
  Screen Sharing serves all of them as one framebuffer, so on a phone every
  desktop is a third of an already small screen and none is usable ("이거 한꺼번에
  모니터 세개가 나오는군", 2026-08-19). It is also the most likely reason
  trackpad hover looked dead on device: the protocol path is proven good
  (`LiveMacPointerHoverTests` — the real pointer moves, 1527 px repaint) and the
  founder confirmed on re-test that the pointer does follow, so the residual
  complaint is scale, not events. Research is measured and recorded in the spec:
  macOS announces **no** screen layout (ExtendedDesktopSize rectangles = 0 with
  the encoding advertised — `LiveMacDisplayLayoutTests`), so display bounds must
  be declared by the user (or reported by the helper) and focus must be a local
  view transform. Blocking input before planning: run
  `swift test --filter LiveMacDisplayLayoutTests` with `NARU_LIVE_MAC_*` pointed
  at the three-display Mac, and check `nc -vz <mac> 5901 5902` — per-display
  ports, if `specs/008/research.md:44` is right about modern macOS, would be a
  better answer than cropping.
- **Specify helper production packaging before implementation** — menu-bar app
  wrapper, notarization, launchd auto-start, capability/status disclosure, and
  revoke/disable UX need a new Spec Kit feature. Today the helper is a dev-only
  CLI (`.build/release/NaruHelper`) plus the `NaruHelperDev.app` TCC wrapper.
- **Real single-profile helper availability probe** — replace the
  refresh-all+poll pattern used by helper onboarding (noted in
  `specs/010-helper-onboarding/plan.md`).
- **`specs/006` open tasks** — T028 helper-side revoke/disable, T029
  physical evidence recording, security/privacy review checklist items.
- **`specs/002` residual manual tests** — T045 vim smoke, T046 Bluetooth
  Magic Keyboard passthrough (physical device).
- **`specs/003` residual manual tests** — T032 trackpad/zoom-to-read on
  physical iPhone, T033 physical Korean IME retest.
- **Accessibility / large-text device pass** — VoiceOver navigation for the
  session controls and connection grid, plus the complete light/dark Dynamic
  Type screenshot matrix. Unit policy and simulator builds are green.
  2026-07-12 finding (fixed): `.accessibilityElement(children: .ignore)` on
  seven interactive dock/session controls dropped their `.isButton` trait —
  VoiceOver read them as plain labels and XCUI `buttons[...]` queries missed
  them (this is what broke the live compose E2E, not the compose logic).
  Fixed by re-adding `.accessibilityAddTraits(.isButton)`; the live-Mac
  compose E2E passes again. Residual: a real-device VoiceOver walk-through
  still pending.
  2026-07-12 follow-up (fixed): the full `UXAuditScreenshotsUITests` suite
  is green again (was 21/34 after the Operation rework). Product fix: a
  chevron-revealed immersive control bar no longer races its own 2.4 s
  auto-hide timer (user reveal pins it; viewport interaction collapses it).
  Harness fixes: diagnostics rows are asserted through the corner-capsule
  sheet, the sticky-modifier capture uses the sessionless detail-start
  path (a fast connect failure was wiping the prelocked modifier), and
  compose typing waits for the keyboard before `typeText`.
- **Korean localization** — String Catalog; founder ICP is Korean-first
  (`ROADMAP.md` ship-readiness list).

## Later (P2)

- **`specs/008` completion** — diagnostics-catalog integration (T011–T012),
  helper action docs (T016), transport explanation labels + benchmark
  evidence (T019–T020), quickstart checks.
- **Track C VNC-fallback perf** — eliminate the ~24 MB framebuffer
  copy-on-write in the apply path (`PERFORMANCE_PARITY_ANALYSIS.md`).
- **Helper delete-op contract** — v1 ladder deletes ride the VNC BackSpace
  key lane only (founder D1); a helper-native delete is a post-v1 contract
  change.
- **Non-macOS host ladder tiers** — `specs/009` Non-Goal; needs its own spec.
- **Phase 8 multi-session coordinator spec; Phase 10 SSH/terminal mode** —
  see `ROADMAP.md` pre-spec gates.

## Standing constraints (do not regress)

- Secrets: Keychain `credentialRef` only; helper token via `--token-env`
  environment indirection; test passwords via env vars; never in argv,
  source, committed files, or logs.
- Multilingual text delivery on macOS Screen Sharing: **X11 Unicode keysyms
  (`0x01000000 | codepoint`) DO render** — verified live 2026-07-13 (Korean/CJK
  land regardless of the remote IME; astral-plane emoji excepted). This
  overturns the earlier `no-input` measurement. Compose default is now
  `keystrokeStream` (Unicode-keysym type-through). Clipboard-paste is Latin-1
  on macOS and drops Korean, so it is a fallback only. **Pending founder D3:
  formally amend constitution §I and spec `009` FR-005 / gate T023 (which
  still assert the old `no-input` rule) to match this evidence before treating
  the keystroke path as constitutionally blessed.**
- iPhone before iPad in every verification matrix (constitution §VI).
- Diagnostic exports use the fixed safe-detail catalog — no raw errors, no
  composed text.
- Don't add new perf timing — read `SessionStreamStats` / the DEBUG
  `SessionPerformanceHUDView`.
- PiP Watch stays watch-only; the Remote Input Dock is a session-only
  surface (hidden pre-connect — that is intentional).
