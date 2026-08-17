# Next Steps

Updated: 2026-08-17 KST.

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
1a. **`specs/012` external pointer & strip completions** — ship-quality
   gaps from the 2026-08-17 audits: BT mouse/trackpad scroll wheel +
   secondary click + pointer-hide/hover, strip hold-repeat, one-tap ⌃C,
   IME-flush barrier before strip emissions, iPad regular-width dock cap.
   Spec drafted; implementation next.
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
   record, App Store screenshots (re-shoot: Direct-mode captures are gone;
   use the new accessory-strip/Type captures), hosted privacy policy URL,
   TestFlight distribution. Founder decision D3 (Live→default) is EXECUTED
   by spec 011 + the constitution §I amendment (2026-08-17).

## Near term (P1)

- **Single RFB read multiplexer (unblocks incoming clipboard)** — the
  installed app always connects through `RFBStreamingClient`, and on that
  path `startIncomingClipboardReceive` is deliberately never called: the
  clipboard reader and the frame pump both `readExactly` on the same
  `NWConnection` and split the FBUpdate header (`NaruRemoteAppModel.swift`
  task #30 comment). So the remote→local clipboard review banner ships
  inert. Fix is one reader that dispatches by `msg_type`; until then
  `SUBMISSION_READINESS.md` §2 #7 carries the ⚠️ and store copy must not
  claim it. Found by the 2026-08-17 code audit (P1-4).
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
