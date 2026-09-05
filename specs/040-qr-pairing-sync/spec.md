# Feature Specification: QR Pairing Sync

**Feature Branch**: `040-qr-pairing-sync`
**Created**: 2026-09-04
**Status**: Implemented 2026-09-04 (offer codec + helper `--pair`/rotation
+ deep link + scanner + confirm sheet + editor surgery; `swift test` 1843
green, iPhone simulator build + `QrPairingScreenshotsUITests` green with
captures in `artifacts/screenshots/qr-pairing/`). Founder decisions of the
clarify round, still binding: full payload (host + helper + VNC password —
the password's non-rotatable exposure is an accepted risk), rotate the
token on every pairing, ship in v1 (superseding the same day's "hide the
helper for v1" — the helper's surface is QR pairing). Residual: founder
physical pass — a real `--pair` QR scanned by a real camera, then a live
helper session; and the editor's Revoke affordance currently lives only
in existing model surfaces (no editor-embedded revoke button shipped in
this round).
**Product**: Naru Remote
**Input**: Founder 2026-09-04, after being walked through a live helper
launch: "이거 되게 귀찮은데 앱 자체에 qr코드 표시기능 넣고 싱크 할 수 있게
만들어줘 … 딥링크 넣고 직접 qr찍어 추가하기 넣고 헬퍼는 아예 일반 접속에다가
옵션으로 넣지 말고 큐알 기반으로 테일스케일 연결을 할 수 있게 지원하고
싶어. 내 컴에 클론되어있는 orca 보면 이 큐알을 이용한 싱크 기능 있는데
참고해줘." Reference studied: `~/repo/orca` (stablyai/orca) —
`src/shared/pairing.ts`, `src/shared/mobile-relay-pairing-offer.ts`,
`src/renderer/src/components/settings/MobilePairingQrSection.tsx`,
`mobile/app/pair-scan.tsx`.

## Problem

The helper's value is real (fast video, confirmed Korean insert) but its
onboarding is measured friction, not imagined: on 2026-09-04 the founder
pairing their own dev Mac needed — a token read out of a dotfile, two TCC
grants that had silently lapsed, knowledge that `--listen` and
`--video-listen` are mutually exclusive per process, and a mandatory
`--profile-fingerprint-env` flag that no top-level doc mentions. Every one
of those was discovered by failure. Spec 010's guided sheet improved on
repo-doc reading but still ends in "copy this secret, paste it on the
phone" — typing a 44-character secret on an iPhone keyboard.

The Orca pattern removes the typing entirely: the trusted Mac displays a
QR carrying a versioned JSON offer (endpoint + per-device token + public
key), and the phone either scans it in-app or opens it via a custom URL
scheme from the system camera. Each code mints a unique device token, so a
photographed screen stops working. Naru adopts the pattern with one
constraint Orca does not have: the Mac side is a terminal CLI, so the QR
must render **in the terminal**, not in a GUI.

## What The QR Carries (wire format)

`naru://pair?code=<base64url(JSON)>` — the code rides a **query
parameter**, not a fragment (orca's measured lesson: Android camera
intents and router layers preserve query params more reliably; iOS is
indifferent).

Payload, version 1:

```json
{
  "v": 1,
  "host": {
    "label": "MacBook Pro",
    "magicDns": "hckim-macbookpro",
    "addresses": ["100.126.136.43"],
    "vncPort": 5900
  },
  "helper": {
    "textPort": 5974,
    "videoPort": 5975,
    "token": "<base64url, 32 bytes>",
    "fingerprint": "sha256:<lowercase hex>"
  },
  "vncPassword": "<string, or null when unknown>"
}
```

- `addresses` carries the Tailscale 100.x IPv6/IPv4 address(es) of every
  active interface so pairing works when MagicDNS is off or the name is
  ambiguous; `magicDns` may be null.
- `fingerprint` is the spec 010 formula: `sha256:` + lowercase hex of
  SHA-256 over the token's UTF-8 bytes. It rotates with the token.
- Parsing is strict, the orca way: scheme `naru:`, URL host exactly `pair`,
  empty path, version literal match, base64url charset check, total code
  length cap, JSON schema caps on every string. A code that fails any
  check yields a fixed-catalog error, never a partially-filled profile.
- Diagnostics and logs never contain the code or its decedents: the
  redaction rule is the `naru://pair?code=` prefix pattern from orca's
  `ephemeral-vm-recipe-diagnostics.ts`, plus the existing safe-catalog
  rule (constitution §IV).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Scan Once, Add Everything (Priority: P1)

From the connections home (or the empty first-launch home), the user taps
**QR 찍어 추가하기**, points the phone at a QR their Mac printed in the
terminal, and sees a confirmation sheet: host label, tailnet address,
what will be saved (profile, VNC password, helper pairing). One tap on
Save and the profile exists, connects over VNC, and speaks to the helper.

**Independent Test**: a decoded `PairingOffer` fixture drives the whole
path without a camera — scanner UI is a thin shell over the same decoder
the deep link uses.

**Acceptance Scenarios**:

1. **Given** the camera permission is granted, **When** a valid QR is
   framed, **Then** the confirm sheet presents label + address + save list
   and nothing is persisted before the user taps Save.
2. **Given** Save, **When** the profile is created, **Then** the VNC
   password and helper token are stored via the existing Keychain
   `credentialRef` path — never on `ConnectionProfile` or in the file
   store — and the helper text/video toggles are enabled.
3. **Given** a host whose label matches an existing profile, **When** Save
   is tapped, **Then** the existing profile is updated in place (re-pair)
   rather than duplicated.

### User Story 2 — System Camera Deep Link (Priority: P1)

The user scans the same QR with the iOS Camera app; iOS offers to open it
in Naru; the app opens straight into the same confirmation sheet.

**Acceptance**: the `naru` URL type is registered (XcodeGen `project.yml`
→ regenerate, never hand-edit); a cold start and a foreground resume both
route `naru://pair?code=…` through the identical decoder + sheet as US-1.

### User Story 3 — Token Rotation Kills Old QRs (Priority: P2)

The Mac re-runs `--pair`; a new token is minted; the phone re-scans and
credentials update. A QR photographed earlier no longer pairs.

**Independent Test**: after rotation, a listener handshake with the old
token is rejected and with the new token accepted (FakeRFBServerKit-style
unit test against the request handler, no live Mac needed).

### User Story 4 — Revoke Stays A First-Class Door (Priority: P2)

The profile shows read-only helper state (paired, transport) with
**Revoke**, which clears the Keychain credential; basic VNC viewing is
unaffected. The constitution §IV revocation guarantee survives the UI
change.

### User Story 5 — No Camera, No Problem (Priority: P3)

Camera denied (or QR unrenderable in a font-hostile terminal): the
Mac prints the raw `naru://pair?code=…` string, and the app's pairing
entry offers a paste field accepting the URL or the bare base64url code
(orca's `parsePairingCode` dual-accept).

## Requirements *(mandatory)*

- **FR-001 (payload)**: `NaruPairingOffer` is a pure Core value type with
  strict encode/decode (scheme/host/version/length/charset rules above)
  and its own tests; no UI or camera type appears in it.
- **FR-002 (token rotation)**: `NaruHelper --pair` mints a fresh 32-byte
  secret each run, persists it to the helper state file, and derives the
  fingerprint. Helper listeners verify pairing secrets **per connection**
  against the state file (not a launch-time snapshot), so rotation takes
  effect without a listener restart and a superseded token is refused
  from its next handshake.
- **FR-003 (terminal QR)**: `--pair` renders the QR in the terminal using
  CoreImage `CIQRCodeGenerator` upscaled to half-block Unicode — no new
  dependency — and always prints the raw code as the copy fallback. It
  ends with a clear-screen prompt (terminal scrollback retains the QR;
  the printed prompt is the mitigation the CLI can offer).
- **FR-004 (secret placement)**: `vncPassword` and `helper.token` exist in
  transit (the QR), in memory, and in Keychain — nowhere else. Not on
  `ConnectionProfile`, not in the profile store, not in logs or
  diagnostics exports (fixed-catalog + `code=` redaction).
- **FR-005 (deep link)**: the `naru` URL type is declared in
  `project.yml` (XcodeGen regenerates the project); cold-start and
  warm-resume links route through one decoder into the US-1 sheet. A link
  whose payload fails validation routes to a fixed-catalog error screen,
  never a crash or a partial save.
- **FR-006 (in-app scanner)**: AVCaptureMetadataOutput, QR-only, with the
  camera-permission-denied path rendering the US-5 paste field instead of
  a dead end.
- **FR-007 (profile editor)**: the helper setup section and token field
  are removed from the profile editor (founder direction: not an option
  in the regular connection flow); the editor shows read-only helper
  state with Revoke (US-4). Spec 010's five-step sheet is retired — its
  intro honesty ("basic viewing works without it") moves to the confirm
  sheet.
- **FR-008 (pair preflight)**: `--pair` prints the fixed-catalog
  Accessibility + Screen Recording status before the QR, so a lapsed
  permission is a printed instruction, not a listener that dies later
  with `fixed safe error` (the 2026-09-04 failure mode).
- **FR-009 (tailnet honesty)**: the confirm sheet probes host
  reachability and, when off-tailnet, says so and points at the Tailscale
  app — no public-internet fallback language (constitution §II).
- **FR-010 (doc sync)**: `AGENTS.md`'s helper section gains the real
  launch contract discovered 2026-09-04: `--listen`/`--video-listen` are
  exclusive per process, and `--video-listen` requires
  `--profile-fingerprint-env`.

## Verification Matrix

| Claim | Method | Command |
| --- | --- | --- |
| Offer encode/decode/reject (scheme, host, version, oversize, charset, dual-accept) | XCTest Core | `swift test --filter NaruPairingOfferTests` |
| Rotation refuses old token / accepts new (request handler) | XCTest NaruHelperKit | `swift test --filter NaruHelperPairingRotationTests` |
| Terminal QR renders non-empty matrix; output contains no secret besides the code itself | XCTest NaruHelperKit | `swift test --filter NaruHelperQrRenderTests` |
| Deep link cold-start + resume → sheet; invalid link → fixed error | XCUITest iPhone sim | `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test` |
| Editor has no helper options; revoke still works | XCUITest + existing editor suites | as above |
| Scanner decodes via injected offer (camera not drivable in CI) | Unit + screenshot | as above |
| Founder end-to-end: real `--pair`, real camera, real connect | Physical (residual gate; supersedes spec 010's T014 as the pairing e2e) | paired device pass |

## Residuals & Accepted Risks

- **VNC password inside the QR (founder decision, 2026-09-04).** The
  helper token rotates per pairing, but the VNC password is a system
  credential Naru cannot invalidate; one photograph of the Mac screen
  during `--pair` yields a durable credential. Terminal scrollback
  retains the QR until cleared. Accepted explicitly in the clarify round;
  revisit if a per-viewer credential ever exists.
- Custom scheme beats nothing: iOS Camera opens `naru://` codes, but
  universal links (`https://`) are more robust from Safari/mail; deferred
  until the project has a domain it is willing to own (no
  public-internet-first product stance changes).
- Sequoia-class TCC re-authorization will keep lapsing permissions;
  FR-008 surfaces the state but only the production menu-bar-app round
  (NEXT_STEPS P1) actually reduces it.
- Live-Mac probes and the benchmark scripts keep their env-var token
  contract; rotation must not break `run-naru-live-benchmark.sh` flows
  that pass a fixed secret (they pin their own token via env, which
  continues to satisfy per-connection verification).

## Open Questions

1. Should `--pair` also *print* the two listener launch lines (env-free,
   reading the state file) so the whole Mac-side flow is one terminal
   transcript? Leaning yes; decided in plan.
2. Multi-host: one Mac can serve one token; does a second phone pairing
   rotate out the first (current single-token design) or do we need a
   token *set*? Orca mints per-device tokens. Single-active-token is v1
   (rotation guarantees); per-device tokens are the follow-up if the
   founder pairs a second device.
