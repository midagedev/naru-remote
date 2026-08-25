# Next Steps

Updated: 2026-08-25 KST.

Cross-feature priority queue for any coding agent (Claude Code, Codex) and
the founder. Per-feature ground truth stays in each `specs/<n>-<slug>/spec.md`
**Status** line and `tasks.md`; this file only orders the work across
features. When you finish or reprioritize an item, update this file in the
same PR.

## Now — ship blockers (P0)

00. **`specs/032` PiP Watch survives a second entry — a crash.** Landed
   2026-08-25. Entering PiP twice in one session terminated the app on the
   founder's device. **The simulator cannot reproduce it**:
   `AVPictureInPictureController.isPictureInPictureSupported()` is false on the
   iPhone 17 Pro simulator (iOS 26.2), so the re-entry UITest skips there. Three
   hazards are closed together because none can be ruled out from here — a
   second controller over the same sample-buffer layer, an unguarded
   `startPictureInPicture()`, and a finite `Int64.max` playback duration — plus
   the delegate that was an empty conformance, which is why app state and system
   state could diverge silently. The decisions now live in
   `PiPWatchControllerLifecycle` (Core, 14 tests under `swift test`) and the
   counts reach the diagnostic export. **Open:** founder device pass on build
   11 — PiP twice, then close from the system chrome and enter again.

00a. **`specs/033` session chrome recomposition.** Landed 2026-08-25. PiP moved
   out of the auto-hiding `⋯` menu into the session control bar as a state-aware
   toggle; the two-pill `Type` / `Compose` dock entry became one capsule with
   the switch inside it; the health capsule collapses to a 28-point icon in the
   bar while the session is healthy and only stands alone over the remote screen
   when it has something to say. Captures for both the healthy and the new
   degraded fixture are recorded in the spec. **Open:** founder device pass on
   build 11.

00b. **Gate quality: `testWrongPassword_showsActionableAuthDiagnostic` cannot
   produce its outcome against this Mac.** Measured 2026-08-25 with a raw
   socket probe, no app involved: this Mac's `screensharingd` offers VNC auth,
   issues a challenge, and then **never sends a SecurityResult** for a wrong
   password — the connection simply goes quiet (10 s and 15 s timeouts, twice,
   30 s apart). The control arm with the correct password returns
   `SecurityResult 0` immediately, so the server is healthy; it just does not
   say "rejected". The app therefore reports a timeout rather than an
   authentication rejection, which is correct, and the test's assertion is
   unproducible. It is the same defect class the suite already recorded once
   ("a default that cannot produce the outcome under test is worse than no
   default"). Fix by making the test skip explicitly when the server withholds
   the result, rather than failing — but the skip has to be narrow enough that a
   genuine misclassification still fails. Not attempted in this round.

00c. **`specs/034` what PiP watches.** Landed 2026-08-25. A tap enters PiP
   framed on the current view; a long press opens the framing choices —
   **Current view**, **Follow activity** (automatic, from the damage rectangles
   the RFB layer already decodes), and a region the user draws. The automatic
   policy is a pure Core value type (`PiPAutoFramingPolicy`, 14 tests): area-
   weighted centring, a legible crop band, a dead zone and a cooldown so the
   window holds still, and idle holds the last framing. The mode persists; the
   drawn region is session-scoped, and `effectivePiPFramingMode` reports what
   PiP will actually do when the two disagree. **Open:** founder device pass on
   build 11 — is the window readable, and does Follow activity land on the
   terminal that is printing. The legible band (≈750 px of crop width, from
   3024 ÷ the app's 4x zoom ceiling) is arithmetic, not a measurement of a real
   PiP window, which no simulator can produce.

00d. **`specs/035` Type mode has to type.** Landed 2026-08-25, from three build-11
   reports in one sentence. (1) **The keyboard sometimes did not come up.** Two
   causes, both closed: the commit controller is `@State` on the dock, so a view
   recreation handed the coordinator a *new* controller while UIKit kept the same
   `UITextView` — the new controller's weak reference was nil and every `focus()`
   was a silent no-op (`attachIfNeeded` on every `updateUIView`); and gaining
   focus itself flips the shell's placement, which recreated the view out from
   under the responder just installed, so raising now goes through the same
   request-expansion-then-focus path the idle capsule takes. Focus requests are
   verified and retried (6 attempts, ~50 ms apart) instead of fired once and
   discarded. Plus FR-001: Type mode's keyboard key now **raises** as well as
   lowers, because with no visible field there was nothing else to tap.
   (2) **The panel was taller than its row.** With no helper the Live tier locks
   to clipboard/ASCII at the first commit, and from then on a two-line transport
   caption and a status sentence each held a row above the keyboard for the rest
   of the session. Spec 009 FR-014's guarantee is kept as a one-word badge
   *inside* the row; only a retained failure still earns a row. (3) **Backspace
   did nothing.** `liveDeleteBackward` returned early whenever the mirror was
   empty — which is on entering Type mode and after every Return, i.e. exactly
   when a terminal user reaches for it. FR-011 is narrowed to what it was
   protecting (no *bulk* delete crosses a seal); one tap now sends one remote
   BackSpace, as the identical control in Compose mode always did.
   **Why no gate caught (2):** `NaruRemoteAppModel(snapshot:)` silently dropped
   `liveTypeThroughMode` and `liveFieldText`, so no fixture could reach the
   founder's configuration. It adopts them now, and
   `KeyboardUpDockHeightUITests` measures the degraded dock. **Open:** founder
   device pass on build 12.

00e. **`specs/036` PiP opens when you ask, and when you leave.** Landed
   2026-08-25. The delay on tap was ours: `AVPictureInPictureController`
   transitions the shared `AVSampleBufferDisplayLayer` into the floating window,
   and that layer was mounted only while `isPiPWatching` — a state the model
   assigns *after* `startPictureInPicture()` in the same synchronous pass. The
   system was asked to fly a layer that was not on screen. It is now mounted for
   the life of the session, behind an opaque fill. The other half of the report
   cannot be delivered literally — **an app has no API to send itself to the
   background** — so `canStartPictureInPictureAutomaticallyFromInline` inverts
   it: leaving the app opens the window, default on, switchable from the PiP
   long-press menu. A system-started window is adopted as a real
   `PiPWatchSession` (it used to be dropped, which would have left the window
   frozen). **Open:** founder device pass on build 12 — both halves are
   diff-and-device claims; PiP is unsupported on the simulator.

00f. **Environmental red, not this build: `LiveMacPointerHoverTests`
   `testServerRepaintsAfterAPointerMove`.** Reproduced twice 2026-08-25 with
   `changedPixelCount=0` after an eight-step pointer sweep across the Dock band.
   Same family as 00b: this Mac's `screensharingd` declines to answer, so the
   test's premise does not hold here rather than the client being wrong. No file
   in the RFB or update-request path was touched by specs 035/036. Needs the
   same narrow-skip treatment as 00b, or a second machine.

0. **`specs/030` full-frame incremental requests — the founder's frame rate.**
   Landed 2026-08-25. Scoping incremental framebuffer requests to the visible
   viewport made Apple Screen Sharing answer roughly twenty times slower
   (540–787 ms average with a p95 at the client's idle timeout, against 33 ms
   full-frame; 0.49–0.74 content fps against 5.66–7.08, three repeats). An
   iPhone showing a wide desktop is always looking at a crop, so this was the
   normal path. Incrementals are now full-frame. **Open:** founder device pass
   on build 9 — does `contentFramesPerSecond` leave `underFive`, and does the
   bandwidth half of the trade show up in `dirtyAreaPermille` /
   `changedPixelsPermille`? Also unmeasured: what full-frame incrementals cost
   on a metered link, which is spec 017's original argument and is untested
   rather than refuted.

0a. **`specs/028` presentation ledger — keep reading it.** The renderer is
   cleared: the founder's build 8 export presented every frame it received
   (11 of 11) with no latch watchdog firing. The ledger is in the diagnostic
   export, so future "it froze" reports should start there rather than with a
   code read.

0b. **`specs/029` — the link is not the constraint.** Measured RTT to the
   founder's iPhone is 41–500 ms (median ~185 ms, direct over mobile), and a
   184 ms modelled round trip adds 212 ms to update latency and nothing else.
   Pipeline depth 1/2/3 are indistinguishable with and without conditioning;
   `requestPipelineDepth` is unchanged. The conditioning harness is validated.

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
1j. **`specs/022` region-request liveness — fixed 2026-08-21 (build 4
   freeze)**. Founder on device: first frame arrived, then no further frames
   once they interacted. Cause: the pump parked 3 pipelined incremental
   requests carrying the region current when they were sent and refilled only
   after a *consumed* response, so any viewport change (pan, zoom, or the
   dock/keyboard shrinking the visible area — which is what turns spec 017
   region scoping on) left every parked request describing an area the user
   had left; RFB answers a request only with damage inside its own region, so
   the session deadlocked. Live-measured 7/8 receives held. Fixed by making
   the region part of the parked-set identity (re-park on viewport change,
   widen to full-frame on hold, widen counter for observability). **Gate gap
   closed**: the fakes had no region semantics, so no unit/simulator test
   could fail on a stale region — a region-aware fake now reproduces the dead
   stream deterministically in 0.2 s. Simulator E2E liveness gate landed
   2026-08-21 (T005 — the lead reproduces the freeze itself). Remaining: HUD
   surfacing of the widen counter (T006).
1k. **`specs/023` trackpad-first pointing — implemented 2026-08-21**. Three
   founder findings in one gesture loop. (a) `PointerControlMode.productDefault`
   is now `.trackpad` — precision pointing is the phone baseline, not the
   exception — and the cursor is centred the moment the remote coordinate space
   arrives so the first drag does not walk the pointer out of the origin.
   (b) The pan clamp gained a vertical breathing band (`min(96, height*0.16)`,
   only on an overflowing axis) so the remote screen's bottom row can be parked
   clear of the floating input dock; trackpad mode has no one-finger pan, so
   auto-pan reaching into the band is the only way there. Verified visually
   FAIL-first: with the band at 0 the remote Dock row sits behind the
   Type/Compose pill. (c) Both cursor render paths placed the fallback glyph's
   *box centre* on the click point, and the SF Symbol's tip is 6.5pt left /
   10pt above that centre (measured) — a ~12pt lie. `TrackpadCursorGlyph` now
   owns the artwork and its measured tip offset for both paths, and the Metal
   path stopped squashing the arrow into a 22×22 box. Remaining: founder device
   pass (T006).
1l. **`specs/024` partial upload coalescing — implemented 2026-08-21**. Founder
   report "트랙패드 잘 되는데 이게 왜 이렇게 반응이 느리지". Measured: the input
   path is clean (outbound pointer queue/op `0 / 0 ms`); the picture is the
   ceiling. ~~With every client pacing floor removed on loopback the server
   still produces only 9.4 content fps, so ~10 fps is Screen Sharing's own
   request/response cadence.~~ **Retracted 2026-08-21 (spec 025)** — that came
   from a debug-built benchmark with a 12 Hz stimulus as the only moving
   content, so it was bounded by the stimulus and inflated by unoptimised
   decode. Release build at 30 Hz: 13.7 content fps, 16.1 delivered — and with
   the instrument fully corrected (see 1o), **17.0 content / ~20 delivered at
   111 ms delivery latency**. There is no ~10 fps server ceiling. Trackpad still
   did not slow anything — it put a display-rate local cursor next to a ~17 fps
   picture.
   Inside that, the benchmark's own primary issue was
   `full-upload-failed`: the upload plan re-uploaded the entire framebuffer
   whenever damage arrived as more than 64 rectangles, even though damage
   averaged 0.5% of the screen (rect count peaked at 112 — a scrolling
   terminal). Rectangles are now merged (least-added-area over raster
   neighbours) instead, with `uploadRegions` as the single owner the renderer
   also uploads from. Live A/B with an identical controlled stimulus: full
   uploads **200‰ → 0‰**, issue cleared. fps/decode unchanged on this Mac —
   the phone-side bandwidth/power win is inferred, not measured, so a device
   pass is the confirmation.
   **Helper video is still the answer to the transport itself**: Screen
   Recording is already granted on the founder's Mac (`helper-dev-app-setup`
   reports `granted`), and real ScreenCaptureKit capture measured
   `frameRateBucket: upTo30`, `sustainedUpdateBand: smooth`,
   `decodePressure: low`, verdict `pass`. Remaining for spec 007 is the
   30-minute sustained run, which needs the physical iPhone gate (the Mac-side
   probe clamps to 120 frames), plus spec 010 T014 pairing so the phone
   actually selects that transport.
1m. **`specs/025` release-configuration measurement instrument — implemented
   2026-08-21**. `scripts/run-naru-live-benchmark.sh` contained the word
   `release` zero times: every mode built and ran **debug**, and debug Swift
   leaves ZRLE inflate/tile-apply unoptimised so client processing dominated
   every latency it reported. Same target, same stimulus, same flags, changing
   only the configuration: debug read 0.78 content fps and diagnosed
   `local-processing-dominated`; release read 7.68 and diagnosed
   `first-byte-wait-dominated` — a different conclusion about where the
   bottleneck is. Two judgements had already been contaminated: the 9.4 fps
   "server ceiling" above, and the `requestPipelineDepth: 3` justification
   comment, whose cited numbers are debug-range. Fixed structurally — one owner
   for the build configuration defaulting to release, every invocation and bin
   path qualified by it (including `--show-bin-path`, which reports the debug
   path unqualified and silently won a candidate search), `buildConfiguration`
   stated on every report with a warning line in debug text output, and a
   `measurement-configuration-self-test` mode that fails on an unqualified
   invocation, a hardcoded debug path, or a non-release default (FAIL-first
   confirmed on all three). Depth re-measured properly: eight 15 s release runs
   per arm, depth 1 median 7.7 fps vs depth 3 median 8.6, ranges fully
   overlapping, depth 1 winning 41% of pairwise comparisons — **no measurable
   difference**, so the constant stays at 3 and the comment now says so.
1n. **`specs/026` damage-count cliff removal — implemented 2026-08-21**. Spec
   024's merge kept a rectangle-count ceiling at 512 above which a frame skips
   merging and takes a full upload. Release-built measurement found this server
   sends ~713 rectangles (peak 738) for frames that changed only 34–39% of the
   screen, so the new ceiling re-created the defect spec 024 closed, at
   **174‰** of content frames (median of eight runs). Attributed by
   intervention: lifting only the ceiling under an identical stimulus took it to
   0‰. Closed by shape rather than by constant — no rectangle count sends a
   frame to a full upload any more; above `quadraticMergeInputCeiling` (1024, vs
   a measured peak of 738) a linear pass unions raster-order runs so the merge
   cost stays bounded for any count. A 256 ceiling was tried first and measured
   *worse* (57‰) because the blunt pass inflates area past the 60% rule, which
   is now pinned as its own test. Live result: **174‰ → 0‰**, `full-upload-failed`
   no longer primary in any run. Merge cost 0.33 ms per frame at the live peak
   (cost caching took it down from 1.2 ms), 0.65 ms at the ceiling. fps
   unchanged on this Mac — phone-side win still inferred, device pass confirms.
   **Open, not closed**: picture staleness. The visual-freshness marker reads a
   median of ~0.9–1.3 s of age with a p95 of 7–13 s while update latency
   averages 31 ms. That gap is where the founder's "느리다" actually lives, and
   it is untouched. The metric is bimodal across otherwise identical runs
   (three of sixteen read ~210–265 ms average), so it needs its own instrument
   audit before it is trusted as a target. **That audit is now done — see 1o.**
1o. **`specs/027` freshness per delivery — implemented 2026-08-21**. The
   staleness metric did not survive changing the run length: peak reported
   staleness was 0.98 s in a 5 s run, 6.8 s in 15 s and **31.8 s in 40 s**, all
   else held. Cause: the benchmark framebuffer is persistent, so a marker the
   server has not re-sent decodes again on every later update, and the probe
   timed every decode — one undelivered marker became a run of samples whose age
   only grew (FAIL-first shows it directly: 9 → 258 → 262 → 267 ms for re-reads
   of one marker). Freshness is now sampled once per marker **delivery**, and a
   fixed marker-status label separates `not-observed` / `stalled` (the host
   stopped painting — an occluded stimulus window would previously have read as
   transport staleness forever) / `tracking`. Delivery and re-read counts are
   published, and a round-trip test pins them against the hand-written
   encoder/decoder pair that dropped them on the first attempt.
   Two further defects were found by continuing rather than stopping at the
   first: the sidecar timestamp was written from the frame timer *before* the
   repaint it requested, so it meant "intended at" rather than "rendered at"
   (fixed — but re-measurement showed it was **not** the cause, so the paint-
   scheduling hypothesis is rejected); and the marker decoder produces
   **false positives** — it scans every cell size 96→8 across several bands,
   returns the first match, and validates only four sentinel nibbles plus a
   four-bit checksum, which is twenty bits against millions of candidate
   positions per frame. A false match preempts the real marker and, when its
   bogus sequence happens to exist in the sidecar, charges the entire elapsed run
   to the transport. Rejected now by three stimulus properties in a specific
   order (rendered / not ahead of newest / never counts down); the first two must
   precede the monotonic high-water mark, because one false match with a huge
   sequence otherwise blinds the probe permanently — that looked like success
   (maxima collapsed) while deliveries fell from 22–37 to 1–8 per run. Pinned as
   its own test.
   A **fourth** defect was then found by asking why the report could only account
   for 32–55% of its own elapsed wall clock: the exhaustive marker search was
   eating the rest. Probe off vs on, everything else held — content fps
   **17.8 vs 8.1**, accounted time **97–98% vs 32–55%**. So every frame-rate
   number ever taken from a freshness-enabled run in this repo was depressed by
   roughly half by the instrument. Two obvious fixes were measured and did
   nothing (caching the marker placement; reading the sidecar incrementally
   instead of re-parsing ~1000 lines per observation — kept anyway, but not the
   cause), because the cost is in the frame where the marker does *not* decode:
   the full search runs, finds nothing, and pays the maximum price to learn that.
   A failed search now buys silence for 60 observations.
   **Corrected numbers for the VNC path** (real Screen Sharing, loopback, 30 Hz
   stimulus, release build): **content 17.0 fps, delivered ~20 fps, picture
   delivery latency 111 ms average / 135 ms p95**, 88–95% of elapsed time
   accounted for, probe overhead ~5%.
   **This retires the "VNC is stuck near 10 fps" line everywhere in this repo.**
   The founder's "느리다" was being diagnosed against numbers that were half real.
   Helper video (`upTo30`, `smooth`, `decodePressure: low`) is still the higher
   ceiling and still blocked on spec 010 T014 pairing — but it is now an
   improvement over a working baseline, not a rescue.
   **Next lever, and the only gate item left on this target.** With the
   instrument corrected, `iphone-remote-desktop-10fps-v1` no longer reports
   `content-fps-failed` at all; the sole remaining issue is client-side
   processing (`client-processing-warning`, avg 8–9 ms, p95 30–32 ms with the
   probe off — the probe's residual ~5% is enough to push that p95 over the fail
   line, so freshness-enabled runs still read `client-processing-failed`). That
   p95 is the decode/upload tail on the high-damage frames (~700 damage
   rectangles), which is where the next real work is if this path is pushed
   further.
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
