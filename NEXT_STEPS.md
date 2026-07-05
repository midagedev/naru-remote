# Next Steps

Updated: 2026-07-05 KST.

Cross-feature priority queue for any coding agent (Claude Code, Codex) and
the founder. Per-feature ground truth stays in each `specs/<n>-<slug>/spec.md`
**Status** line and `tasks.md`; this file only orders the work across
features. When you finish or reprioritize an item, update this file in the
same PR.

## Now — ship blockers (P0)

1. **Commit / PR the 2026-07-05 working tree** — Live type-through
   (`specs/009`), helper onboarding (`specs/010`), NaruHelper hardening,
   `PERFORMANCE_PARITY_ANALYSIS.md`, and this documentation refresh. The tree
   is verified green: `swift test` 1473 tests / 0 failures, iPhone 17 Pro
   simulator build succeeded.
2. **`specs/009` physical gates T021–T025** (`specs/009-live-type-through/tasks.md`):
   200-char Korean/English/number/symbol integrity ×10, per-commit latency
   p95, Unicode-KeyEvent no-input regression, 30-min sustained live session,
   non-macOS-host residual note. Requires the paired physical iPhone and the
   founder's Mac; VNC/helper credentials go through environment variables
   only — never into source, docs, or shell history.
3. **`specs/007` real-screen helper-video gate** — one human click: run
   `bash scripts/run-naru-live-benchmark.sh helper-dev-app-setup` on the Mac
   and approve Screen Recording, then re-run
   `physical-iphone-helper-video-gate` (the synthetic-source gate already
   passed 2026-07-05).
4. **Founder decision D3 execution** — once the 009 gates pass, promote Live
   to the default multilingual input path and amend
   `.specify/memory/constitution.md` §I accordingly.
5. **App Store Connect human steps** (`SUBMISSION_READINESS.md` §5.4) — app
   record, App Store screenshots, hosted privacy policy URL, TestFlight
   distribution.

## Near term (P1)

- **Helper production packaging** — menu-bar app wrapper, notarization,
  launchd auto-start. Today the helper is a dev-only CLI
  (`.build/release/NaruHelper`) plus the `NaruHelperDev.app` TCC wrapper.
- **Real single-profile helper availability probe** — replace the
  refresh-all+poll pattern used by helper onboarding (noted in
  `specs/010-helper-onboarding/plan.md`).
- **`specs/006` open tasks** — T028 helper-side revoke/disable, T029
  physical evidence recording, security/privacy review checklist items.
- **`specs/002` residual manual tests** — T045 vim smoke, T046 Bluetooth
  Magic Keyboard passthrough (physical device).
- **`specs/003` residual manual tests** — T032 trackpad/zoom-to-read on
  physical iPhone, T033 physical Korean IME retest.
- **Korean localization** — String Catalog; founder ICP is Korean-first
  (`SUBMISSION_READINESS.md` P2 list).

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
- Unicode/multilingual text never goes out as VNC KeyEvents on macOS —
  measured `no-input` (see `PERFORMANCE_PARITY_ANALYSIS.md`); use helper
  nativeInsert or clipboard-paste.
- iPhone before iPad in every verification matrix (constitution §VI).
- Diagnostic exports use the fixed safe-detail catalog — no raw errors, no
  composed text.
- Don't add new perf timing — read `SessionStreamStats` / the DEBUG
  `SessionPerformanceHUDView`.
- PiP Watch stays watch-only; the Remote Input Dock is a session-only
  surface (hidden pre-connect — that is intentional).
