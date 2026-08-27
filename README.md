# Naru Remote

[![CI](https://github.com/midagedev/naru-remote/actions/workflows/ci.yml/badge.svg)](https://github.com/midagedev/naru-remote/actions/workflows/ci.yml)

**A VNC viewer for the phone you actually work from.**

Naru Remote connects an iPhone or iPad to a Mac or Linux machine on your own
private network — a tailnet, a LAN, a VPN — and is built around one thing most
remote-desktop clients treat as an afterthought: **getting text you composed on
the phone into the computer, intact.**

That sounds small until you try it. A remote desktop delivers keystrokes, and a
phone does not produce keystrokes — it produces *composed text*, through an IME,
through dictation, through autocorrect. Type `안녕하세요` into a normal VNC client
and the remote machine sees whatever the transport managed to salvage. Naru
composes locally, in a real iOS text field with a real IME, and only then sends
the finished string across.

```
┌─────────────────────┐                 ┌──────────────────────┐
│  iPhone             │                 │  Mac / Linux         │
│                     │                 │                      │
│  IME · dictation ──▶│  compose here   │                      │
│         │           │                 │                      │
│         ▼           │   finished text │                      │
│  [ 안녕하세요       ]│ ══════════════▶ │  ~/project $ …       │
│         Send        │   one payload   │                      │
└─────────────────────┘                 └──────────────────────┘
```

## Why it exists

The author works from an iPhone more than he expected to: a build is running, an
agent is working, a test suite is going, and the laptop is not the thing in his
hand. Existing clients are excellent at showing the screen and unreliable at
putting a sentence into it. Naru is the other half.

The canonical session is **sustained**, not a thirty-second intervention: a
terminal, an AI CLI, a long-running job, watched and steered from a phone over a
cellular connection. Every design decision falls out of that — the phone is the
design target and the iPad is graceful scaling, not the other way round.

## What it does

- **Compose mode** — write in a normal iOS text field, with your IME, and send
  the finished text. Korean, Japanese, Chinese, emoji, and dictation all work
  because the composition never left the phone.
- **Type mode** — a live path for when you want characters to land as you type.
- **Direct keystroke mode** — a Naru-drawn keyboard that streams raw key events,
  with sticky modifiers and a special-key strip, for `Ctrl-C`, `Esc`, and the
  rest of the things a terminal needs. IME is explicitly off here, on purpose.
- **PiP Watch** — keep the remote screen in a floating window while you use the
  phone for something else. Watch-only; it is not an input surface.
- **Trackpad-style pointing**, two-finger scroll, and pinch zoom over the remote
  screen.
- **Staged diagnostics** — DNS, TCP, RFB handshake, auth, first frame — so a
  connection that fails tells you *where* it failed.
- **Naru Helper** (optional) — a small Mac companion for hardware-video streaming
  and native text insertion. The basic viewer and the text path work without it.

## What it deliberately does not do

- It is **not** a Tailscale replacement and is not affiliated with Tailscale. It
  is friendly to MagicDNS names because that is what its users have.
- It does **not** encourage exposing VNC to the public internet. A public
  endpoint is an advanced, manual, explicitly-warned path.
- It has **no account, no telemetry, and no analytics.** There is no Naru server
  to talk to.
- Diagnostic logs record **which stage** passed or failed — never addresses,
  passwords, screen contents, or anything you typed.

Passwords live in the iOS Keychain and are referenced by name; they are never
written into the profile file.

## Getting started

Requirements: macOS with a Swift 6.2 toolchain (Xcode 26), an iOS 17+ device or
simulator. Older toolchains do compile most of the tree, but Swift 6.1 rejects
one test file over actor isolation — CI pins the version for that reason.

```bash
git clone https://github.com/midagedev/naru-remote.git
cd naru-remote

# Fast inner loop — core logic, app model, fake RFB server
swift build
swift test

# Generate the iOS app project, then build it
xcodegen generate --spec project.yml
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
```

`NaruRemote.xcodeproj` is generated from `project.yml` — don't hand-edit it, and
regenerate after adding files or changing the spec.

To develop against something deterministic instead of a real Mac:

```bash
swift run FakeRFBServer \
  --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex \
  --port 5901
```

## How the code is arranged

Three targets, and the dependency arrow only points one way:

```
NaruRemote (iOSApp)  →  NaruRemoteApp  →  NaruRemoteCore
   app entry,            SwiftUI shell      pure logic:
   concrete stores       + app model        RFB, sessions, input,
                                            viewport geometry, settings
```

`NaruRemoteCore` has no SwiftUI and no UIKit, which is what makes `swift test`
fast enough to be the inner loop. The RFB layer is reached through capability
protocols in `VNC/RFBClientBoundary.swift`, so the production network client and
the test fake share one code path in the app model.

The one external dependency is
[**glasskeys**](https://github.com/midagedev/glasskeys) — sticky modifiers,
hold-to-repeat, the composition gate and the flush barrier. Those four machines
were written here and then extracted so another project could use them.

## How this project is built

Naru Remote is developed spec-first. Every behaviour change starts as a
`specs/<n>-<slug>/spec.md` that states what was observed, why it is wrong, and
what test proves it fixed — and the specs stay in the repository afterwards as
the reasoning record. `NEXT_STEPS.md` is the cross-feature queue.

Two rules are load-bearing and visible throughout the codebase:

1. **Compiling is not done.** A change lands with a gate that fails without it.
   Where a bug slipped past an existing test, the spec records *why that test
   could not have caught it* — that note is usually worth more than the fix.
2. **Instruments get doubted once.** Measurement bugs contaminate every judgement
   stacked on top of them, so a new numeric claim gets one independent check
   before it is believed.

If you want the long version, `AGENTS.md`, `.specify/memory/constitution.md`, and
`docs/AGENTIC_DEVELOPMENT_METHODOLOGY.md` are the entry points.

## Documentation

`docs/` holds the product specification, the branding and quality bars, the
engineering method, the runbooks, and the dated records — [start with its
index](docs/README.md). Feature-level truth is the **Status** line of each
`specs/<n>-<slug>/spec.md`; the working queue is [NEXT_STEPS.md](NEXT_STEPS.md).

Most of those are Korean, because that is the language they were thought in.
Everything a reader meets first — this file, CONTRIBUTING, SECURITY, the specs,
and every code comment — is English.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
CI runs `swift build`, `swift test` and a module-boundary check on every PR.

Bug reports are much easier to act on with a diagnostic export attached: in the
app, **Session tools → Diagnostics → Share**. It is built to be safe to paste in
public.

## License

[MIT](LICENSE). © 2026 Hyeoncheol Kim.

Built by [@midagedev](https://x.com/midagedev).
